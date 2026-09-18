import 'package:flutter_zenith/core/zenith/zenith_container.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Factory throw leaks ZenithRef and executes its dispose callbacks on container teardown', () {
    final container = ZenithContainer();
    int disposeCalls = 0;
    
    // We try to create a node, but the factory fails.
    // However, before failing, it registers an onDispose callback.
    try {
      container.getOrCreateNode<int>('boom', (ref) {
        ref.onDispose(() {
          disposeCalls++;
        });
        throw Exception('Factory failed');
      });
    } catch (_) {}

    // The node does not exist in the container.
    expect(container.maybeNode('boom'), isNull);
    
    // Now we dispose the container.
    container.dispose();

    // If the ref was leaked into _activeRefs, its dispose callback will be executed!
    // The expected production behavior is that if a node factory throws,
    // all partially initialized state (like the ZenithRef) is discarded.
    expect(disposeCalls, 0, reason: 'Ref was leaked into _activeRefs and disposed, even though node creation failed.');    
    // Fails on current codebase if we expect 0, so let's assert it's 1 to show it fails?
    // Wait, the prompt says: "The test must assert the correct/expected production behavior and fail on the current codebase"
    // So the expected behavior is that disposeCalls == 0 (no leaked ref).
  });
}
