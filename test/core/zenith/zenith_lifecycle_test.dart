import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zenith/flutter_zenith.dart';

class _CallbackSubscriber implements ZenithSubscriber {
  final void Function(ZenithNode<dynamic> node) callback;

  _CallbackSubscriber(this.callback);

  @override
  void onNodeChanged(ZenithNode<dynamic> node) => callback(node);
}

void main() {
  group('Zenith lifecycle', () {
    test('container.dispose executes all ref.onDispose callbacks', () {
      final container = ZenithContainer();
      var callbacksTriggered = 0;

      container.getOrCreateNode<int>('a', (ref) {
        ref.onDispose(() => callbacksTriggered++);
        return 1;
      });

      container.getOrCreateNode<int>('b', (ref) {
        ref.onDispose(() => callbacksTriggered++);
        return 2;
      });

      container.dispose();

      expect(callbacksTriggered, 2);
      expect(container.isDisposed, isTrue);
    });

    test('updating a disposed node throws StateError', () {
      final node = ZenithNode<int>(0);

      node.dispose();

      expect(() => node.set(1), throwsStateError);
      expect(() => node.invalidate(), throwsStateError);
      expect(() => node.value, throwsStateError);
    });

    test(
      'async work guarded by ref.isMounted does not mutate after disposal',
      () async {
        final container = ZenithContainer();
        late ZenithRef ref;
        final node = container.getOrCreateNode<int>('count', (capturedRef) {
          ref = capturedRef;
          return 0;
        });

        var attemptedMutation = false;

        Future<void> delayedUpdate() async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          if (!ref.isMounted) {
            return;
          }
          attemptedMutation = true;
          node.set(10);
        }

        final future = delayedUpdate();
        container.dispose();
        await future;

        expect(ref.isMounted, isFalse);
        expect(attemptedMutation, isFalse);
        expect(node.isDisposed, isTrue);
      },
    );

    test('child containers do not fall back to parent nodes', () {
      final parent = ZenithContainer();
      parent.getOrCreateNode<int>('shared', (_) => 1);

      final child = ZenithContainer(parent: parent);

      expect(child.maybeNode<int>('shared'), isNull);
      expect(child.maybeNode<int>('missing'), isNull);
    });

    test('invalidation cycles are short-circuited by reentrancy guard', () {
      final nodeA = ZenithNode<int>(1);
      final nodeB = ZenithNode<int>(2);

      var nodeAHits = 0;
      var nodeBHits = 0;

      nodeA.subscribe(
        _CallbackSubscriber((_) {
          nodeAHits++;
          nodeB.invalidate();
        }),
      );

      nodeB.subscribe(
        _CallbackSubscriber((_) {
          nodeBHits++;
          nodeA.invalidate();
        }),
      );

      expect(() => nodeA.invalidate(), returnsNormally);
      expect(nodeAHits, 1);
      expect(nodeBHits, 1);
    });

    test('notification tolerates subscriber mutation during callback', () {
      final node = ZenithNode<int>(0);

      final lateSubscriber = _CallbackSubscriber((_) {});
      late final _CallbackSubscriber mutatingSubscriber;
      mutatingSubscriber = _CallbackSubscriber((changedNode) {
        changedNode.subscribe(lateSubscriber);
        changedNode.unsubscribe(mutatingSubscriber);
      });

      node.subscribe(mutatingSubscriber);

      expect(() => node.set(1), returnsNormally);
      expect(node.debugSubscriberCount, 1);
    });
  });
}
