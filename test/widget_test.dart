import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zenith/flutter_zenith.dart';

void main() {
  test('package API smoke test', () {
    final node = ZenithNode<int>(0);
    node.set(5);

    expect(node.value, 5);
  });
}
