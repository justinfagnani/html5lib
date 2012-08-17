#!/bin/bash
# Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
# for details. All rights reserved. Use of this source code is governed by a
# BSD-style license that can be found in the LICENSE file.

# Script to run all tests in the webcomponents package. For this script to run
# correctly, you need to have a SDK installation and set the following
# environment variable:
#   > export DART_SDK=<SDK location>
#
# If you already have a dart_lang checkout, you can build the SDK directly.

DART=$DART_SDK/bin/dart
# TODO(sigmund): generalize to run browser tests too
for test in tests/*_test.dart; do
  $DART --enable-asserts --enable-type-checks --package-root=packages/ $test
done
