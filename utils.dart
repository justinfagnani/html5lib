/** Misc things that were useful when porting the code from Python. */
#library('utils');

#import('constants.dart');

class Pair<F extends Hashable, S extends Hashable> implements Hashable {
  final F first;
  final S second;

  const Pair(this.first, this.second);

  int hashCode() => 37 * first.hashCode() + second.hashCode();
  operator ==(other) => other.first == first && other.second == second;
}

int parseIntRadix(String str, [int radix = 10]) {
  int val = 0;
  for (int i = 0; i < str.length; i++) {
    var digit = str.charCodeAt(i);
    if (digit >= LOWER_A) {
      digit += 10 - LOWER_A;
    } else if (digit >= UPPER_A) {
      digit += 10 - UPPER_A;
    } else {
      digit -= ZERO;
    }
    val = val * radix + digit;
  }
  return val;
}

/** Simple way of testing if [char] is in [characters]. */
bool inStr(String char, String characters) {
  if (char == null) return false;
  return characters.indexOf(char) >= 0;
}

String joinStr(List<String> strings) => Strings.join(strings, '');

// Like the python [:] operator.
List slice(List list, int start, [int end]) {
  if (end == null) end = list.length;
  if (end < 0) end += list.length;

  // Ensure the indexes are in bounds.
  if (end < start) end = start;
  if (end > list.length) end = list.length;
  return list.getRange(start, end - start);
}

removeAt(List list, int i) {
  var result = list[i];
  list.removeRange(i, 1);
  return result;
}

typedef bool Predicate();
