import 'package:flutter_zenith/core/zenith/zenith_container.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Failed factory releases its resources exactly once', () {
    final container = ZenithContainer();
    var disposeCalls = 0;
    expect(
      () => container.getOrCreateNode<int>('boom', (ref) {
        ref.onDispose(() => disposeCalls++);
        throw StateError('Factory failed');
      }),
      throwsStateError,
    );
    expect(container.maybeNode('boom'), isNull);
    expect(disposeCalls, 1);
    container.dispose();
    expect(disposeCalls, 1);
  });
}
