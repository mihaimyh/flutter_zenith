import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zenith/flutter_zenith.dart';

class ValueReader implements ZenithSubscriber {
  final ZenithNode<int> node;
  ValueReader(this.node);
  @override
  void onNodeChanged(ZenithNode<dynamic> _) {
    node.value;
  }
}

void main() {
  test('reading computed value in subscriber must not create a cycle', () {
    final source = ZenithNode(1);
    final derived = ComputedNode(() => source.value * 2);
    final reader = ValueReader(derived);
    final cancel = derived.subscribe(reader);
    source.value = 2;
    expect(() => source.value = 3, returnsNormally);
    expect(derived.value, 6);
    cancel();
    derived.dispose();
    source.dispose();
  });
}
