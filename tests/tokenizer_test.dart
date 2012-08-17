#library('tokenizer_test');

// Note: mirrors used to match the getattr usage in the original test
#import('dart:io');
#import('dart:json');
#import('dart:mirrors');
#import('package:unittest/unittest.dart');
#import('../tokenizer.dart');
#import('../constants.dart', prefix: 'constants');
#import('../codecs.dart');
#import('support.dart');

main() {
  testTokenizer();
}

/**
 * This is like [JSON.parse], but it fixes unicode surrogate pairs in the JSON.
 *
 * Without this, the test "expects" incorrect results from the tokenizer.
 * Note: Python's json module decodes these correctly, so this might point at
 * a bug in Dart's [JSON.parse].
 */
jsonParseUnicode(String input) => jsonFixSurrogatePairs(JSON.parse(input));

// TODO(jmesserly): this should probably be handled by dart:json
jsonFixSurrogatePairs(jsonObject) {
  fixSurrogate(object) {
    if (object is String) {
      return decodeUtf16Surrogates(object);
    } else if (object is List) {
      List a = object;
      for (int i = 0; i < a.length; i++) {
        a[i] = fixSurrogate(a[i]);
      }
    } else if (object is Map) {
      Map<String, Object> m = object;
      m.forEach((key, value) {
        var fixedKey = fixSurrogate(key);
        var fixedValue = fixSurrogate(value);
        if (fixedKey !== key) {
          m.remove(key);
          m[fixedKey] = fixedValue;
        } else if (fixedValue !== value) {
          m[fixedKey] = fixedValue;
        }
      });
    }
    return object;
  }
  return fixSurrogate(jsonObject);
}


class TokenizerTestParser {
  String _state;
  var _lastStartTag;
  List outputTokens;

  TokenizerTestParser(String initialState, [lastStartTag])
      : _state = initialState,
        _lastStartTag = lastStartTag;

  List parse(stream, [encoding, innerHTML = false]) {
    var tokenizer = new HTMLTokenizer(stream, encoding);
    outputTokens = [];

    // Note: we can't get a closure of the state method. However, we can
    // create a new closure to invoke it via mirrors.
    var mirrors = currentMirrorSystem();
    var mtok = mirrors.mirrorOf(tokenizer);
    // TODO(jmesserly): mirrors are causing us to lose stack traces?
    // If you hit a bug and aren't getting a stack trace, consider adding
    // debug code like this to avoid the mirror invocation:
    //     if (_state == 'dataState') {
    //        tokenizer.state = tokenizer.dataState;
    //     } else {
    // Replace 'dataState' with the appropriate state name.
    tokenizer.state = () => mtok.invoke(_state, const []).value.reflectee;

    if (_lastStartTag != null) {
      tokenizer.currentToken = {"type": "startTag", "name": _lastStartTag};
    }

    var types = new Map<int, String>();
    constants.tokenTypes.forEach((k, v) => types[v] = k);
    while (tokenizer.hasNext()) {
      var token = tokenizer.next();
      mirrors.mirrorOf(this).invoke(
          'process${types[token["type"]]}', [mirrors.mirrorOf(token)]);
    }

    return outputTokens;
  }

  /** Makes a dictionary, where the first key wins. */
  Map _makeDict(List<List> items) {
    var result = new Map();
    for (var item in items) {
      expect(item.length, equals(2));
      result.putIfAbsent(item[0], () => item[1]);
    }
    return result;
  }

  void processDoctype(Map token) {
    outputTokens.add(["DOCTYPE", token["name"], token["publicId"],
        token["systemId"], token["correct"]]);
  }

  void processStartTag(Map token) {
    outputTokens.add(["StartTag", token["name"],
        _makeDict(token["data"]), token["selfClosing"]]);
  }

  void processEmptyTag(Map token) {
    if (constants.voidElements.indexOf(token["name"]) >= 0) {
      outputTokens.add("ParseError");
    }
    outputTokens.add(["StartTag", token["name"], _makeDict(token["data"])]);
  }

  void processEndTag(Map token) {
    outputTokens.add(["EndTag", token["name"], token["selfClosing"]]);
  }

  void processComment(Map token) {
    outputTokens.add(["Comment", token["data"]]);
  }

  void processSpaceCharacters(Map token) {
    processCharacters(token);
  }

  void processCharacters(Map token) {
    outputTokens.add(["Character", token["data"]]);
  }

  void processEOF(token) {
  }

  void processParseError(Map token) {
    // TODO(jmesserly): when debugging test failures it can be useful to add
    // logging here like `print('ParseError $token');`. It would be nice to
    // use the actual logging library.
    outputTokens.add(["ParseError", token["data"]]);
  }
}

List concatenateCharacterTokens(List tokens) {
  var outputTokens = [];
  for (var token in tokens) {
    if (token.indexOf("ParseError") == -1 && token[0] == "Character") {
      if (outputTokens.length > 0 &&
          outputTokens.last().indexOf("ParseError") == -1 &&
          outputTokens.last()[0] == "Character") {

        outputTokens.last()[1] = '${outputTokens.last()[1]}${token[1]}';
      } else {
        outputTokens.add(token);
      }
    } else {
      outputTokens.add(token);
    }
  }
  return outputTokens;
}

List normalizeTokens(List tokens) {
  // TODO: convert tests to reflect arrays
  for (int i = 0; i < tokens.length; i++) {
    var token = tokens[i];
    if (token[0] == 'ParseError') {
      tokens[i] = token[0];
    }
  }
  return tokens;
}


/**
 * Test whether the test has passed or failed
 *
 * If the ignoreErrorOrder flag is set to true we don't test the relative
 * positions of parse errors and non parse errors.
 */
void expectTokensMatch(List expectedTokens, List receivedTokens,
    bool ignoreErrorOrder, [bool ignoreErrors = false, String message]) {

  var checkSelfClosing = false;
  for (var token in expectedTokens) {
    if (token[0] == "StartTag" && token.length == 4
        || token[0] == "EndTag" && token.length == 3) {
      checkSelfClosing = true;
      break;
    }
  }

  if (!checkSelfClosing) {
    for (var token in receivedTokens) {
      if (token[0] == "StartTag" || token[0] == "EndTag") {
        token.removeLast();
      }
    }
  }

  if (!ignoreErrorOrder && !ignoreErrors) {
    expect(receivedTokens, equals(expectedTokens), message);
  } else {
    // Sort the tokens into two groups; non-parse errors and parse errors
    var expectedParseErrors = expectedTokens.filter((t) => t == "ParseError");
    var expectedNonErrors = expectedTokens.filter((t) => t != "ParseError");
    var receivedParseErrors = receivedTokens.filter((t) => t == "ParseError");
    var receivedNonErrors = receivedTokens.filter((t) => t != "ParseError");

    expect(receivedNonErrors, equals(expectedNonErrors), message);
    if (!ignoreErrors) {
      expect(receivedParseErrors, equals(expectedParseErrors), message);
    }
  }
}

// TODO(jmesserly): I had to use this trampoline to get reasonable stack traces
// from the unit test framework.
/*
void runTokenizerTest(Map testInfo) {
  try {
    runTokenizerTest2(testInfo);
  } catch (var e, var trace) {
    print('exception $e');
    print('trace $trace');
    exit(1);
  }
}
*/

void runTokenizerTest(Map testInfo) {
  // XXX - move this out into the setup function
  // concatenate all consecutive character tokens into a single token
  if (testInfo.containsKey('doubleEscaped')) {
    testInfo = unescape(testInfo);
  }

  var expected = concatenateCharacterTokens(testInfo['output']);
  if (!testInfo.containsKey('lastStartTag')) {
    testInfo['lastStartTag'] = null;
  }
  var parser = new TokenizerTestParser(testInfo['initialState'],
      testInfo['lastStartTag']);
  var tokens = parser.parse(testInfo['input']);
  tokens = concatenateCharacterTokens(tokens);
  var received = normalizeTokens(tokens);
  var errorMsg = Strings.join(["\n\nInitial state:",
              testInfo['initialState'],
              "\nInput:", testInfo['input'],
              "\nExpected:", expected,
              "\nreceived:", tokens].map((s) => '$s'), '\n');
  var ignoreErrorOrder = testInfo['ignoreErrorOrder'];
  if (ignoreErrorOrder == null) ignoreErrorOrder = false;

  expectTokensMatch(expected, received, ignoreErrorOrder, true, errorMsg);
}

Map unescape(Map testInfo) {
  // Note: using JSON.parse to unescape the unicode characters in the string.
  decode(inp) => jsonParseUnicode('"${inp}"');

  testInfo["input"] = decode(testInfo["input"]);
  for (var token in testInfo["output"]) {
    if (token == "ParseError") {
      continue;
    } else {
      token[1] = decode(token[1]);
      if (token.length > 2) {
        for (var pair in token[2]) {
          var key = pair[0];
          var value = pair[1];
          token[2].remove(key);
          token[2][decode(key)] = decode(value);
        }
      }
    }
  }
  return testInfo;
}


String camelCase(String s) {
  s = s.toLowerCase();
  var result = new StringBuffer();
  for (var match in const RegExp(@"\W+(\w)(\w+)").allMatches(s)) {
    if (result.length == 0) result.add(s.substring(0, match.start()));
    result.add(match.group(1).toUpperCase());
    result.add(match.group(2));
  }
  return result.toString();
}

void testTokenizer() {
  getDataFiles('tokenizer', (p) => p.endsWith('.test')).then((files) {
    for (var path in files) {

      var text = new File.fromPath(new Path(path)).readAsTextSync();
      var tests = jsonParseUnicode(text);
      var testName = new Path.fromNative(path).filename.replaceAll(".test","");
      var testList = tests['tests'];
      if (testList == null) continue;

      group(testName, () {
        for (int index = 0; index < testList.length; index++) {
          final testInfo = testList[index];

          testInfo.putIfAbsent("initialStates", () => ["Data state"]);
          for (var initialState in testInfo["initialStates"]) {
            test(testInfo["description"], () {
              testInfo["initialState"] = camelCase(initialState);
              runTokenizerTest(testInfo);
            });
          }
        }
      });
    }
  });
}
