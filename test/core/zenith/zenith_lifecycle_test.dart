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

    test(
      'updating a disposed node is a silent no-op; invalidate/value still throw',
      () {
        final node = ZenithNode<int>(0);

        node.dispose();

        // set() fails softly now -- no exception, no mutation.
        expect(() => node.set(1), returnsNormally);
        // invalidate() and the value getter still throw for disposed nodes.
        expect(() => node.invalidate(), throwsStateError);
        expect(() => node.value, throwsStateError);
      },
    );

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

    test('ref.set() mutates while mounted and silently no-ops once disposed', () {
      final container = ZenithContainer();
      late ZenithRef ref;
      final node = container.getOrCreateNode<int>('count', (capturedRef) {
        ref = capturedRef;
        return 0;
      });

      ref.set(node, 5);
      expect(node.value, 5);

      container.dispose();

      expect(() => ref.set(node, 10), returnsNormally);
      expect(node.isDisposed, isTrue);
    });

    test(
      'ref.runAsync() resolves to AsyncData while mounted and no-ops after '
      'disposal',
      () async {
        final container = ZenithContainer();
        late ZenithRef ref;
        final node = container.getOrCreateNode<AsyncValue<int>>(
          'asyncCount',
          (capturedRef) {
            ref = capturedRef;
            return const AsyncData<int>(0);
          },
        );

        await ref.runAsync(node, () async => 42);

        expect(node.value, isA<AsyncData<int>>());
        expect((node.value as AsyncData<int>).value, 42);

        final pendingRunAsync = ref.runAsync(node, () async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return 99;
        });

        container.dispose();

        await expectLater(pendingRunAsync, completes);
        expect(node.isDisposed, isTrue);
      },
    );

    test(
      'ZenithNode.guard() extension delegates to ref.runAsync() safely',
      () async {
        final container = ZenithContainer();
        late ZenithRef ref;
        final node = container.getOrCreateNode<AsyncValue<String>>(
          'guardedNode',
          (capturedRef) {
            ref = capturedRef;
            return const AsyncData<String>('');
          },
        );

        await node.guard(ref, () async => 'hello');
        expect((node.value as AsyncData<String>).value, 'hello');

        final pendingGuard = node.guard(ref, () async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          throw StateError('boom');
        });

        container.dispose();

        await expectLater(pendingGuard, completes);
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
