#library('inputstream');

#import('dart:io');
#import('dart:utf');
#import('codecs.dart', prefix: 'codecs');
#import('constants.dart');
#import('utils.dart');
#import('encoding_parser.dart');


/**
 * Provides a unicode stream of characters to the HTMLTokenizer.
 *
 * This class takes care of character encoding and removing or replacing
 * incorrect byte-sequences and also provides column and line tracking.
 */
class HTMLInputStream {

  const int _defaultChunkSize = 10240;

  /** List of where new lines occur. */
  List newLines;

  /**
   * Number of bytes to use when looking for a meta element with
   * encoding information.
   */
  const int numBytesMeta = 512;

  /** Encoding to use if no other information can be found. */
  const String defaultEncoding = "windows-1252";

  /** The name of the character encoding. */
  String charEncodingName;

  /** True if we are certain about [charEncodingName], false for tenative. */
  bool charEncodingCertain = true;

  List<int> rawBytes;

  Iterator<int> dataStream;

  /** Cache for charsUntil() */
  Map charsUntilRegEx;

  List<String> errors;

  String chunk;

  int chunkOffset;

  /** number of (complete) lines in previous chunks */
  int prevNumLines;

  /** number of columns in the last line of the previous chunk */
  int prevNumCols;

  /** Deals with CR LF and surrogates split over chunk boundaries */
  String _bufferedCharacter;

  /**
   * Initialises the HTMLInputStream.
   *
   * HTMLInputStream(source, [encoding]) -> Normalized stream from source
   * for use by html5lib.
   *
   * [source] can be either a [RandomAccessFile], a [String], or a [List<int>]
   * containing the raw bytes.
   *
   * The optional encoding parameter must be a string that indicates
   * the encoding.  If specified, that encoding will be used,
   * regardless of any BOM or later declaration (such as in a meta
   * element)
   *
   * [parseMeta] - Look for a <meta> element containing encoding information
   */
  HTMLInputStream(source, [String encoding, bool parseMeta = true])
      : newLines = [0],
        charEncodingName = codecName(encoding),
        charsUntilRegEx = new Map() {

    if (source is String) {
      // TODO(jmesserly): if the data is already a string, we should just use
      // the source.charCodes() instead of wasting time encoding/decoding.
      rawBytes = encodeUtf8(source);
      charEncodingName = 'utf-8';
      charEncodingCertain = true;
    } else if (source is RandomAccessFile) {
      // TODO(jmesserly): it's unfortunate we need to read all bytes in advance,
      // but it's necessary because of how the UTF decoders work.
      rawBytes = readAllBytesFromFile(source);
    } else if (source is List<int>) {
      rawBytes = source;
    } else {
      // TODO(jmesserly): we should accept some kind of stream API too.
      // Unfortunately dart:io InputStream is async only, which won't work.
      throw new IllegalArgumentException(
          'source must be a String, RandomAccessFile, or List<int>');
    }

    // Detect encoding iff no explicit "transport level" encoding is supplied
    if (charEncodingName == null) {
      detectEncoding(parseMeta);
    }

    reset();
  }

  void reset() {
    dataStream = null;
    chunk = "";
    chunkOffset = 0;
    errors = [];
    prevNumLines = 0;
    prevNumCols = 0;
    _bufferedCharacter = null;
  }


  void detectEncoding([bool parseMeta = true]) {
    // First look for a BOM
    // This will also read past the BOM if present
    charEncodingName = detectBOM();
    charEncodingCertain = true;

    // If there is no BOM need to look for meta elements with encoding
    // information
    if (charEncodingName === null && parseMeta) {
      charEncodingName = detectEncodingMeta();
      charEncodingCertain = false;
    }
    // If all else fails use the default encoding
    if (charEncodingName === null) {
      charEncodingCertain = false;
      charEncodingName = defaultEncoding;
    }

    // Substitute for equivalent encodings:
    if (charEncodingName.toLowerCase() == "iso-8859-1") {
      charEncodingName = "windows-1252";
    }
  }

  void changeEncoding(String newEncoding) {
    newEncoding = codecName(newEncoding);
    if (const ["utf-16", "utf-16-be", "utf-16-le"].indexOf(newEncoding) >= 0) {
      newEncoding = "utf-8";
    }
    if (newEncoding === null) {
      return;
    } else if (newEncoding == charEncodingName) {
      charEncodingCertain = true;
    } else {
      reset();
      charEncodingName = newEncoding;
      charEncodingCertain = true;
      throw new Exception(
          "Encoding changed from $charEncodingName to $newEncoding");
    }
  }

  /**
   * Attempts to detect at BOM at the start of the stream. If
   * an encoding can be determined from the BOM return the name of the
   * encoding otherwise return null.
   */
  String detectBOM() {
    // Try detecting the BOM using bytes from the string
    if (codecs.hasUtf8Bom(rawBytes)) {
      return 'utf-8';
    }
    // Note: we don't need to remember whether it was big or little endian
    // because the decoder will do that later. It will also eat the BOM for us.
    if (hasUtf16Bom(rawBytes)) {
      return 'utf-16';
    }
    if (hasUtf32Bom(rawBytes)) {
      return 'utf-32';
    }
    return null;
  }

  /** Report the encoding declared by the meta element. */
  String detectEncodingMeta() {
    var parser = new EncodingParser(slice(rawBytes, 0, numBytesMeta));
    var encoding = parser.getEncoding();

    if (const ["utf-16", "utf-16-be", "utf-16-le"].indexOf(encoding) >= 0) {
      encoding = "utf-8";
    }

    return encoding;
  }

  List<int> _position(offset) {
    var nLines = 0;
    for (int i = 0; i < offset; i++) {
      if (chunk.charCodeAt(i) == NEWLINE) nLines++;
    }
    var positionLine = prevNumLines + nLines;
    var lastLinePos = chunk.lastIndexOf('\n', offset);
    var positionColumn;
    if (lastLinePos == -1) {
      positionColumn = prevNumCols + offset;
    } else {
      positionColumn = offset - (lastLinePos + 1);
    }
    return [positionLine, positionColumn];
  }

  /** Returns (line, col) of the current position in the stream. */
  List<int> position() {
    var pos = _position(chunkOffset);
    pos[0] += 1;
    return pos;
  }

  /**
   * Read one character from the stream or queue if available. Return
   * EOF when EOF is reached.
   */
  String char() {
    // Read a new chunk from the input stream if necessary
    if (chunkOffset >= chunk.length) {
      if (!readChunk()) {
        return EOF;
      }
    }

    return chunk[chunkOffset++];
  }


  // TODO(jmesserly): fix the performance of this method. Lots of things would
  // be better dealt with in the tokenizer. At the very least we should try to
  // avoid so many allocations...
  bool readChunk([int readSize]) {
    if (readSize === null) {
      readSize = _defaultChunkSize;
    }

    var pos = _position(chunk.length);
    prevNumLines = pos[0];
    prevNumCols = pos[1];

    chunk = "";
    chunkOffset = 0;

    if (dataStream == null) {
      // perform the initial decode
      dataStream = codecs.decodeBytes(charEncodingName, rawBytes).iterator();
    }
    var charCodes = [];
    for (int i = 0; i < readSize && dataStream.hasNext(); i++) {
      charCodes.add(dataStream.next());
    }
    var data = codepointsToString(charCodes);

    // Deal with CR LF and surrogates broken across chunks
    if (_bufferedCharacter != null) {
      data = '${_bufferedCharacter}${data}';
      _bufferedCharacter = null;
    } else if (data.length == 0) {
      // We have no more data, bye-bye stream
      return false;
    }

    if (data.length > 1) {
      var lastv = data.charCodeAt(data.length - 1);
      if (lastv == 0x0D || 0xD800 <= lastv && lastv <= 0xDBFF) {
        _bufferedCharacter = data[data.length - 1];
        data = data.substring(0, data.length - 1);
      }
    }

    // Replace invalid characters
    // Note U+0000 is dealt with in the tokenizer
    chunk = replaceCharacters(data);

    return true;
  }

  /**
   * Returns a string of characters from the stream up to but not
   * including any character in 'characters' or EOF.
   */
  String charsUntil(String characters, [bool opposite = false]) {
    // Use a cache of regexps to find the required characters
    var regexpKey = new Pair(characters, opposite ? 'opposite' : '');
    var chars = charsUntilRegEx[regexpKey];

    if (chars == null) {
      escapeChar(c) {
        assert(c < 128);
        var hex = c.toRadixString(16);
        hex = (hex.length == 1) ? "0$hex" : hex;
        return "\\u00$hex";
      }
      var regex = joinStr(characters.charCodes().map(escapeChar));
      if (!opposite) {
        regex = "^${regex}";
      }
      chars = charsUntilRegEx[regexpKey] = new RegExp("^[${regex}]+");
    }

    var rv = [];
    while (true) {
      // Find the longest matching prefix
      // TODO(jmesserly): RegExp does not seem to offer a start offset?
      var searchChunk = chunk.substring(chunkOffset);
      var m = chars.firstMatch(searchChunk);
      if (m === null) {
        // If nothing matched, and it wasn't because we ran out of chunk,
        // then stop
        if (chunkOffset != chunk.length) {
          break;
        }
      } else {
        assert(m.start() == 0);
        var end = m.end();
        // If not the whole chunk matched, return everything
        // up to the part that didn't match
        if (end != chunk.length - chunkOffset) {
          rv.add(searchChunk.substring(0, end));
          chunkOffset += end;
          break;
        }
      }
      // If the whole remainder of the chunk matched,
      // use it all and read the next chunk
      rv.add(searchChunk);
      if (!readChunk()) {
        // Reached EOF
        break;
      }
    }
    return joinStr(rv);
  }

  void unget(String ch) {
    // Only one character is allowed to be ungotten at once - it must
    // be consumed again before any further call to unget
    if (ch != null) {
      if (chunkOffset == 0) {
        // unget is called quite rarely, so it's a good idea to do
        // more work here if it saves a bit of work in the frequently
        // called char and charsUntil.
        // So, just prepend the ungotten character onto the current
        // chunk:
        chunk = '${ch}${chunk}';
      } else {
        chunkOffset -= 1;
        assert(chunk[chunkOffset] == ch);
      }
    }
  }

  String replaceCharacters(String str) {
    // TODO(jmesserly): it'd be nice not to create the array until we know we
    // are replacing something. Also it'd be nice to set the initial capacity.
    var result = <int>[];
    for (int i = 0; i < str.length; i++) {
      var c = str.charCodeAt(i);
      if (invalidUnicode(c)) errors.add("invalid-codepoint");

      if (0xD800 <= c && c <= 0xDFFF) {
        c = 0xFFFD;
      } else if (c == RETURN) {
        int j = i + 1;
        if (j < str.length && str.charCodeAt(j) == NEWLINE) {
          i = j; // \r\n becomes \n
        }
        c = NEWLINE;
      }
      result.add(c);
    }
    return codepointsToString(result);
  }
}


// TODO(jmesserly): the Python code used a regex to check for this. But
// Dart doesn't let you create a regexp with invalid characters.
bool invalidUnicode(int c) {
  if (0x0001 <= c && c <= 0x0008) return true;
  if (0x000E <= c && c <= 0x001F) return true;
  if (0x007F <= c && c <= 0x009F) return true;
  if (0xD800 <= c && c <= 0xDFFF) return true;
  if (0xFDD0 <= c && c <= 0xFDEF) return true;
  switch (c) {
    case 0x000B: case 0xFFFE: case 0xFFFF: case 0x01FFFE: case 0x01FFFF:
    case 0x02FFFE: case 0x02FFFF: case 0x03FFFE: case 0x03FFFF:
    case 0x04FFFE: case 0x04FFFF: case 0x05FFFE: case 0x05FFFF:
    case 0x06FFFE: case 0x06FFFF: case 0x07FFFE: case 0x07FFFF:
    case 0x08FFFE: case 0x08FFFF: case 0x09FFFE: case 0x09FFFF:
    case 0x0AFFFE: case 0x0AFFFF: case 0x0BFFFE: case 0x0BFFFF:
    case 0x0CFFFE: case 0x0CFFFF: case 0x0DFFFE: case 0x0DFFFF:
    case 0x0EFFFE: case 0x0EFFFF: case 0x0FFFFE: case 0x0FFFFF:
    case 0x10FFFE: case 0x10FFFF:
      return true;
  }
  return false;
}

List<int> readAllBytesFromFile(RandomAccessFile file) {
  int length = file.lengthSync();
  var bytes = new List<int>(length);

  int bytesRead = 0;
  while (bytesRead < length) {
    int read = file.readListSync(bytes, bytesRead, length - bytesRead);
    if (read <= 0) {
      // This could happen if, for example, the file was resized while
      // we're reading. Just shrink the bytes array and move on.
      bytes = bytes.getRange(0, bytesRead);
      break;
    }
    bytesRead += read;
  }
  return bytes;
}

/**
 * Return the python codec name corresponding to an encoding or null if the
 * string doesn't correspond to a valid encoding.
 */
String codecName(String encoding) {
  final asciiPunctuation = const RegExp(
      "[\u0009-\u000D\u0020-\u002F\u003A-\u0040\u005B-\u0060\u007B-\u007E]");

  if (encoding == null) return null;
  var canonicalName = encoding.replaceAll(asciiPunctuation, '').toLowerCase();
  return encodings[canonicalName];
}
