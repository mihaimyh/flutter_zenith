import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zenith/flutter_zenith.dart';

void main() {
  group('ZenithContainer.reset()', () {
    test('disposes all managed nodes and runs onDispose hooks', () {
      final container = ZenithContainer();
      var disposeHooksRun = 0;

      final node1 = container.getOrCreateNode<int>('count', (ref) {
        ref.onDispose(() => disposeHooksRun++);
        return 10;
      });

      final node2 = container.getOrCreateNode<String>('user', (ref) {
        ref.onDispose(() => disposeHooksRun++);
        return 'Alice';
      });

      expect(node1.value, 10);
      expect(node2.value, 'Alice');

      // Perform in-place container reset
      container.reset();

      // Container is still alive (not permanently disposed)
      expect(container.isDisposed, isFalse);

      // Dispose hooks fired
      expect(disposeHooksRun, 2);

      // Old nodes are disposed
      expect(node1.isDisposed, isTrue);
      expect(node2.isDisposed, isTrue);
      expect(() => node1.value, throwsStateError);
      expect(() => node2.value, throwsStateError);

      // Old keys are cleared from storage map
      expect(container.maybeNode<int>('count'), isNull);
      expect(container.maybeNode<String>('user'), isNull);
    });

    test('allows creating fresh nodes after reset', () {
      final container = ZenithContainer();

      final nodeA = container.getOrCreateNode<int>('x', (_) => 100);
      expect(nodeA.value, 100);

      container.reset();

      final nodeB = container.getOrCreateNode<int>('x', (_) => 200);
      expect(identical(nodeA, nodeB), isFalse);
      expect(nodeB.value, 200);
    });

    test('is a safe no-op on a disposed container', () {
      final container = ZenithContainer();
      container.dispose();

      expect(container.reset, returnsNormally);
      expect(container.isDisposed, isTrue);
    });
  });
}
