// Comprehensive production-readiness suite for Zenith.
//
// Verifies memory safety, thread/async safety, and Flutter widget-tree
// integration against the concrete engine rules implemented in:
//   - lib/core/zenith/zenith_container.dart (ZenithContainer, ZenithRef)
//   - lib/core/zenith/zenith_node.dart (ZenithNode, weak subscriber set)
//   - lib/core/zenith/zenith_widgets.dart (ZenithScope, ZenithBuilder)
//   - lib/core/zenith/async_value.dart (AsyncValue/AsyncData/AsyncLoading/AsyncError)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zenith/flutter_zenith.dart';

/// Generic mock subscriber that forwards `onNodeChanged` to a callback.
/// Useful for asserting notification order, counts, and re-entrancy.
class _CallbackSubscriber implements ZenithSubscriber {
  _CallbackSubscriber(this.onChanged);

  final void Function(ZenithNode<dynamic> node) onChanged;

  @override
  void onNodeChanged(ZenithNode<dynamic> node) => onChanged(node);
}

/// A subscriber whose only job is to exist and be counted, so it can be
/// dropped out of scope to exercise `WeakReference` collection.
class _EphemeralSubscriber implements ZenithSubscriber {
  int notifyCount = 0;

  @override
  void onNodeChanged(ZenithNode<dynamic> node) => notifyCount++;
}

void main() {
  // ===========================================================================
  // Suite 1: Container Lifecycle & Memory Safety (User Logout / Multi-Tenancy)
  // ===========================================================================
  group('Suite 1: Container Lifecycle & Memory Safety', () {
    test(
      'Test 1.1: Multi-user logout teardown disposes nodes, runs onDispose '
      'hooks, and releases references',
      () {
        final containerA = ZenithContainer();
        var disposeHooksRun = 0;

        final userIdNode = containerA.getOrCreateNode<String>('userId', (
          ref,
        ) {
          ref.onDispose(() => disposeHooksRun++);
          return 'user-A';
        });

        final sessionNode = containerA.getOrCreateNode<int>('sessionTtl', (
          ref,
        ) {
          ref.onDispose(() => disposeHooksRun++);
          return 3600;
        });

        expect(containerA.isDisposed, isFalse);
        expect(userIdNode.value, 'user-A');
        expect(sessionNode.value, 3600);

        containerA.dispose();

        // Container flips to disposed synchronously.
        expect(containerA.isDisposed, isTrue);

        // Every ZenithRef.onDispose hook fired exactly once.
        expect(disposeHooksRun, 2);

        // Nodes are destroyed: reading them now throws instead of returning
        // stale user data (critical for multi-tenant leak prevention).
        expect(() => userIdNode.value, throwsStateError);
        expect(() => sessionNode.value, throwsStateError);
        expect(userIdNode.isDisposed, isTrue);
        expect(sessionNode.isDisposed, isTrue);

        // The internal node/ref maps are released; new lookups for the same
        // key surface no leftover state.
        expect(containerA.maybeNode<String>('userId'), isNull);

        // Disposing twice must be a safe no-op (idempotent teardown).
        expect(containerA.dispose, returnsNormally);
        expect(disposeHooksRun, 2);
      },
    );

    testWidgets(
      'Test 1.2: Container swap in UI tree disposes the old container '
      'immediately via didUpdateWidget',
      (tester) async {
        final containerA = ZenithContainer();
        final containerB = ZenithContainer();
        containerA.getOrCreateNode<int>('x', (_) => 1);
        containerB.getOrCreateNode<int>('x', (_) => 2);

        Widget host(ZenithContainer container) {
          return MaterialApp(
            home: ZenithScope(
              container: container,
              child: Builder(
                builder: (context) {
                  final current = ZenithScope.of(context);
                  return Text(
                    'value:${current.maybeNode<int>('x')?.value}',
                    textDirection: TextDirection.ltr,
                  );
                },
              ),
            ),
          );
        }

        // No key is used here on purpose: the widget/element identity stays
        // the same across pumps, so Flutter routes the container swap
        // through `didUpdateWidget` rather than a full unmount/remount.
        await tester.pumpWidget(host(containerA));
        expect(find.text('value:1'), findsOneWidget);
        expect(containerA.isDisposed, isFalse);
        expect(containerB.isDisposed, isFalse);

        await tester.pumpWidget(host(containerB));

        expect(containerA.isDisposed, isTrue);
        expect(containerB.isDisposed, isFalse);
        expect(find.text('value:2'), findsOneWidget);
      },
    );

    test(
      'Test 1.3: Parent-child fallback does not leak or destroy state '
      'across container boundaries',
      () {
        final parent = ZenithContainer();
        final parentNode = parent.getOrCreateNode<int>('shared', (_) => 100);

        final child = ZenithContainer(parent: parent);
        final childNode = child.getOrCreateNode<int>('shared', (_) => 1);

        // The child creates its own independent node under the same key;
        // `getOrCreateNode`/`maybeNode` never silently return the parent's
        // instance.
        expect(identical(childNode, parentNode), isFalse);
        expect(parentNode.value, 100);
        expect(childNode.value, 1);

        // Disposing the child must not touch parent state at all.
        child.dispose();

        expect(child.isDisposed, isTrue);
        expect(childNode.isDisposed, isTrue);
        expect(parent.isDisposed, isFalse);
        expect(parentNode.isDisposed, isFalse);
        expect(parentNode.value, 100);

        // A fresh child container for the same key starts clean -- no
        // leftover state leaks back in from the disposed sibling.
        final child2 = ZenithContainer(parent: parent);
        expect(child2.maybeNode<int>('shared'), isNull);
        final child2Node = child2.getOrCreateNode<int>('shared', (_) => 999);
        expect(child2Node.value, 999);
        expect(parentNode.value, 100);
      },
    );

    test(
      'Test 1.3b: invalidate() bubbles to the parent for missing keys '
      'without materializing a node in the child',
      () {
        final parent = ZenithContainer();
        final parentNode = parent.getOrCreateNode<int>('shared', (_) => 1);
        var parentNotifyCount = 0;
        parentNode.subscribe(
          _CallbackSubscriber((_) => parentNotifyCount++),
        );

        final child = ZenithContainer(parent: parent);
        child.invalidate('shared');

        expect(parentNotifyCount, 1);
        expect(child.maybeNode<int>('shared'), isNull);
      },
    );
  });

  // ===========================================================================
  // Suite 2: Reactive Dependency Graph & Garbage Collection
  // ===========================================================================
  group('Suite 2: Reactive Dependency Graph & Garbage Collection', () {
    test(
      'Test 2.1: dead weak-referenced subscribers are purged from the node '
      'and debugSubscriberCount reflects reality',
      () async {
        final node = ZenithNode<int>(0);

        // Create the subscriber inside a helper so no local variable in this
        // test keeps it alive; only the node's WeakReference points to it.
        void attachEphemeralSubscriber() {
          node.subscribe(_EphemeralSubscriber());
        }

        attachEphemeralSubscriber();
        expect(node.debugSubscriberCount, 1);

        // Allocation pressure loop nudges the VM's GC to collect the
        // now-unreachable subscriber (there is no deterministic manual GC
        // trigger available from Dart test code). The bound is generous to
        // keep this reliable across VM versions/CI machines.
        for (var i = 0; i < 1000 && node.debugSubscriberCount > 0; i++) {
          final pressure = List<Object>.generate(
            8000,
            (index) => 'garbage-$index',
          );
          expect(pressure.length, 8000);
          await Future<void>.delayed(const Duration(milliseconds: 2));
          node.notifySubscribers();
        }

        expect(node.debugSubscriberCount, 0);
      },
      retry: 2,
    );

    testWidgets(
      'Test 2.2: dynamic dependency branching unsubscribes stale nodes so '
      'mutating a no-longer-read node does not trigger a rebuild',
      (tester) async {
        final nodeC = ZenithNode<bool>(true); // true => read A, false => B
        final nodeA = ZenithNode<String>('a-initial');
        final nodeB = ZenithNode<String>('b-initial');

        var buildCount = 0;

        await tester.pumpWidget(
          MaterialApp(
            home: ZenithBuilder(
              builder: (context) {
                buildCount++;
                return Text(
                  nodeC.value ? nodeA.value : nodeB.value,
                  textDirection: TextDirection.ltr,
                );
              },
            ),
          ),
        );

        expect(buildCount, 1);
        expect(nodeC.debugSubscriberCount, 1);
        expect(nodeA.debugSubscriberCount, 1);
        expect(nodeB.debugSubscriberCount, 0);

        // Flip the branch: A is no longer read, B becomes the dependency.
        nodeC.set(false);
        await tester.pump();

        expect(buildCount, 2);
        expect(nodeA.debugSubscriberCount, 0);
        expect(nodeB.debugSubscriberCount, 1);

        // Mutating A -- an unobserved, reconciled-away dependency -- must
        // NOT cause another rebuild.
        nodeA.set('a-mutated-while-unobserved');
        await tester.pump();

        expect(buildCount, 2);

        // Sanity: B still drives rebuilds since it is the live dependency.
        nodeB.set('b-mutated');
        await tester.pump();
        expect(buildCount, 3);
      },
    );

    test(
      'Test 2.3a: invalidate() guards against synchronous re-entrant '
      'self-invalidation via the _isInvalidating flag',
      () {
        final node = ZenithNode<int>(0);
        var notifyCount = 0;

        late final _CallbackSubscriber subscriber;
        subscriber = _CallbackSubscriber((_) {
          notifyCount++;
          // Re-enter invalidate() on the same node from inside the
          // notification callback. Without the guard this would recurse
          // forever and blow the stack.
          node.invalidate();
        });
        node.subscribe(subscriber);

        expect(node.invalidate, returnsNormally);
        // The re-entrant call is short-circuited; only the outer call
        // produces a notification pass.
        expect(notifyCount, 1);
      },
    );

    test(
      'Test 2.3b: circular invalidation between two nodes terminates '
      'without stack overflow',
      () {
        final nodeA = ZenithNode<int>(1);
        final nodeB = ZenithNode<int>(2);
        var aHits = 0;
        var bHits = 0;

        nodeA.subscribe(
          _CallbackSubscriber((_) {
            aHits++;
            nodeB.invalidate();
          }),
        );
        nodeB.subscribe(
          _CallbackSubscriber((_) {
            bHits++;
            nodeA.invalidate();
          }),
        );

        expect(nodeA.invalidate, returnsNormally);
        expect(aHits, 1);
        expect(bHits, 1);
      },
    );

    test(
      'Test 2.3c: re-entrant set() with a converging value stops recursing '
      'because of the value-equality short circuit',
      () {
        final node = ZenithNode<int>(0);
        var callbackInvocations = 0;

        late final _CallbackSubscriber subscriber;
        subscriber = _CallbackSubscriber((changed) {
          callbackInvocations++;
          // Setting the same value again is a no-op (value equality check
          // in `ZenithNode.set`), so this must not recurse.
          changed.set(1);
        });
        node.subscribe(subscriber);

        expect(() => node.set(1), returnsNormally);
        expect(node.value, 1);
        expect(callbackInvocations, 1);
      },
    );
  });

  // ===========================================================================
  // Suite 3: Async & Concurrent Execution
  // ===========================================================================
  group('Suite 3: Async & Concurrent Execution', () {
    test(
      'Test 3.1: out-of-order async resolution does not let a slow, '
      'earlier request overwrite a faster, newer one',
      () async {
        final resultNode = ZenithNode<AsyncValue<String>>(
          const AsyncLoading<String>(),
        );
        var latestRequestId = 0;

        Future<void> fetch(String value, Duration delay) async {
          final requestId = ++latestRequestId;
          await Future<void>.delayed(delay);

          // Consumer-level guard against stale responses: discard results
          // for requests that are no longer the latest in flight.
          if (requestId != latestRequestId) {
            return;
          }
          resultNode.set(AsyncData<String>(value));
        }

        // The first request is slow; the second is fast and issued right
        // after, so it should "win" even though it resolves first.
        final slowStaleRequest = fetch(
          'stale-slow-response',
          const Duration(milliseconds: 50),
        );
        final fastFreshRequest = fetch(
          'fresh-fast-response',
          const Duration(milliseconds: 5),
        );

        await Future.wait<void>([slowStaleRequest, fastFreshRequest]);

        final result = resultNode.value;
        expect(result, isA<AsyncData<String>>());
        expect((result as AsyncData<String>).value, 'fresh-fast-response');
      },
    );

    test(
      'Test 3.2: async work started before disposal fails gracefully '
      'afterward instead of throwing an unhandled async exception',
      () async {
        final container = ZenithContainer();
        late ZenithRef capturedRef;

        final node = container.getOrCreateNode<int>('counter', (ref) {
          capturedRef = ref;
          return 0;
        });

        Object? caughtError;
        var mountedCheckedBeforeMutation = false;

        final pendingWrite = Future<void>(() async {
          await Future<void>.delayed(const Duration(milliseconds: 10));

          mountedCheckedBeforeMutation = true;
          if (!capturedRef.isMounted) {
            // Well-behaved consumer code: bail out instead of mutating.
            return;
          }
          node.set(42);
        });

        // Also verify the un-guarded path no longer throws: ZenithNode.set()
        // fails softly (silent no-op) on a disposed node instead of crashing
        // the isolate/zone.
        final pendingUnguardedWrite = Future<void>(() async {
          await Future<void>.delayed(const Duration(milliseconds: 15));
          try {
            node.set(99);
          } catch (e) {
            caughtError = e;
          }
        });

        container.dispose();
        await Future.wait<void>([pendingWrite, pendingUnguardedWrite]);

        expect(capturedRef.isMounted, isFalse);
        expect(mountedCheckedBeforeMutation, isTrue);
        expect(node.isDisposed, isTrue);
        // Node value was never mutated after disposal.
        expect(() => node.value, throwsStateError);
        // The un-guarded write silently no-oped -- no exception thrown and
        // no unhandled async exception escaped the zone.
        expect(caughtError, isNull);
      },
    );
  });

  // ===========================================================================
  // Suite 4: Flutter Widget Tree & Context Integration
  // ===========================================================================
  group('Suite 4: Flutter Widget Tree & Context Integration', () {
    testWidgets(
      'Test 4.1: rapid key swapping (fast login/logout simulation) never '
      'throws a double-disposal exception',
      (tester) async {
        Widget buildForIteration(int i) {
          final container = ZenithContainer();
          container.getOrCreateNode<int>('n', (_) => i);
          return MaterialApp(
            home: ZenithScope(
              key: ValueKey<int>(i),
              container: container,
              child: const SizedBox.shrink(),
            ),
          );
        }

        for (var i = 0; i < 25; i++) {
          await tester.pumpWidget(buildForIteration(i));
          expect(tester.takeException(), isNull);
        }

        // Final teardown of the last mounted scope must also be clean.
        await tester.pumpWidget(const SizedBox.shrink());
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Test 4.2: ZenithScope.of asserts with an actionable message when the '
      'resolved container has already been disposed',
      (tester) async {
        final container = ZenithContainer();

        Widget buildTree() => MaterialApp(
          home: ZenithScope(
            container: container,
            child: Builder(
              builder: (context) {
                final resolved = ZenithScope.of(context);
                return Text(
                  'disposed:${resolved.isDisposed}',
                  textDirection: TextDirection.ltr,
                );
              },
            ),
          ),
        );

        await tester.pumpWidget(buildTree());
        expect(tester.takeException(), isNull);
        expect(find.text('disposed:false'), findsOneWidget);

        // Dispose the container directly (independent of the widget tree)
        // to simulate a stale BuildContext referencing a torn-down scope.
        container.dispose();

        // Rebuilding re-invokes Builder.build -> ZenithScope.of(context),
        // which must hit the `assert(!container.isDisposed)` guard.
        await tester.pumpWidget(buildTree());

        final exception = tester.takeException();
        expect(exception, isA<AssertionError>());
        expect(exception.toString(), contains('disposed'));
      },
    );
  });
}
