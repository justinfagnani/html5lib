#library('support');
#import('dart:io');

final testDataDir = '';

typedef bool FileMatcher(String fileName);

Future<List<String>> getDataFiles(String subdirectory, [FileMatcher matcher]) {
  if (matcher == null) matcher = (path) => path.endsWith('.dat');

  // TODO(jmesserly): should have listSync for scripting...
  // This entire method was one line of Python code
  var dir = new Directory.fromPath(new Path('tests/data/$subdirectory'));
  var lister = dir.list();
  var files = <String>[];
  lister.onFile = (file) {
    if (matcher(file)) files.add(file);
  };
  var completer = new Completer<List<String>>();
  lister.onDone = (success) {
    completer.complete(files);
  };
  return completer.future;
}
