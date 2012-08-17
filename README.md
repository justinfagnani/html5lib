html5lib in Pure Dart
=====================

This is a pure [Dart][dart] [html5 parser][html5lib]. It's a port of
[html5lib](http://code.google.com/p/html5lib/) from Python. Since it's 100%
Dart you can use it safely from a script or server side app.

Eventually the parse tree API will be compatible with [dart:html][d_html], so
the same code will work on the client or the server.

This library is not finished. These files from the [html5lib directory][files]
still need to be ported:

* `html5parser.py`
* `ihatexml.py`
* `sanitizer.py`
* `filters/*`
* `serializer/*`
* `treebuilders/*`
* `treewalkers/*`
* most of `tests`


Running Tests
-------------

Dependencies are installed using the [Pub Package Manager][pub].

    pub install

    # Run command line tests
    #export DART_SDK=path/to/dart/sdk
    tests/run.sh


[dart]: http://www.dartlang.org/
[html5lib]: http://dev.w3.org/html5/spec/parsing.html
[d_html]: http://api.dartlang.org/docs/continuous/dart_html.html
[files]: http://html5lib.googlecode.com/hg/python/html5lib/
