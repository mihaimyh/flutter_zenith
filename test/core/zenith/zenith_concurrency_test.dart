import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zenith/flutter_zenith.dart';

int _double(int x) => x * 2;

void main() {
  group('ZenithConcurrencyX.runAsyncGuarded — droppable', () {
    test('ignores a new call while a task is actively loading', () async {
      final container = ZenithContainer();
      late ZenithRef ref;
      final node = container.getOrCreateNode<AsyncValue<int>>('n', (r) {
        ref = r;
        return const AsyncData(0);
      });

      final completer1 = Completer<int>();
      final future1 = ref.runAsyncGuarded<int>(
        node,
        () => completer1.future,
        strategy: ConcurrencyStrategy.droppable,
      );

      var secondTaskStarted = false;
      final future2 = ref.runAsyncGuarded<int>(
        node,
        () async {
          secondTaskStarted = true;
          return 999;
        },
        strategy: ConcurrencyStrategy.droppable,
      );

      await future2;
      expect(secondTaskStarted, isFalse);
      expect(node.value.isLoading, isTrue);

      completer1.complete(1);
      await future1;

      expect(node.value, isA<AsyncData<int>>());
      expect((node.value as AsyncData<int>).value, 1);

      container.dispose();
    });

    test('allows a new call once the prior task has completed', () async {
      final container = ZenithContainer();
      late ZenithRef ref;
      final node = container.getOrCreateNode<AsyncValue<int>>('n', (r) {
        ref = r;
        return const AsyncData(0);
      });

      await ref.runAsyncGuarded<int>(
        node,
        () async => 1,
        strategy: ConcurrencyStrategy.droppable,
      );
      await ref.runAsyncGuarded<int>(
        node,
        () async => 2,
        strategy: ConcurrencyStrategy.droppable,
      );

      expect((node.value as AsyncData<int>).value, 2);

      container.dispose();
    });
  });

  group('ZenithConcurrencyX.runAsyncGuarded — restartable (default)', () {
    test('drops a stale result from an earlier, slower call', () async {
      final container = ZenithContainer();
      late ZenithRef ref;
      final node = container.getOrCreateNode<AsyncValue<int>>('n', (r) {
        ref = r;
        return const AsyncData(0);
      });

      final completer1 = Completer<int>();
      final future1 = ref.runAsyncGuarded<int>(node, () => completer1.future);
      final future2 = ref.runAsyncGuarded<int>(node, () async => 2);

      await future2;
      expect((node.value as AsyncData<int>).value, 2);

      // The stale first call resolves later; it must not overwrite state.
      completer1.complete(1);
      await future1;

      expect((node.value as AsyncData<int>).value, 2);

      container.dispose();
    });

    test('drops stale errors from an earlier, slower call', () async {
      final container = ZenithContainer();
      late ZenithRef ref;
      final node = container.getOrCreateNode<AsyncValue<int>>('n', (r) {
        ref = r;
        return const AsyncData(0);
      });

      final completer1 = Completer<int>();
      final future1 = ref.runAsyncGuarded<int>(node, () => completer1.future);
      final future2 = ref.runAsyncGuarded<int>(node, () async => 2);

      await future2;
      expect((node.value as AsyncData<int>).value, 2);

      completer1.completeError(Exception('boom'));
      await future1;

      expect(node.value, isA<AsyncData<int>>());
      expect((node.value as AsyncData<int>).value, 2);

      container.dispose();
    });

    test('with 3 rapid calls, only the true latest result lands', () async {
      final container = ZenithContainer();
      late ZenithRef ref;
      final node = container.getOrCreateNode<AsyncValue<int>>('n', (r) {
        ref = r;
        return const AsyncData(0);
      });

      final completer1 = Completer<int>();
      final completer2 = Completer<int>();
      final future1 = ref.runAsyncGuarded<int>(node, () => completer1.future);
      final future2 = ref.runAsyncGuarded<int>(node, () => completer2.future);
      final future3 = ref.runAsyncGuarded<int>(node, () async => 3);

      await future3;
      expect((node.value as AsyncData<int>).value, 3);

      completer2.complete(2);
      await future2;
      expect((node.value as AsyncData<int>).value, 3);

      completer1.complete(1);
      await future1;
      expect((node.value as AsyncData<int>).value, 3);

      container.dispose();
    });
  });

  group('ZenithConcurrencyX.runAsyncGuarded — concurrent', () {
    test('last call to complete wins, even if it started first', () async {
      final container = ZenithContainer();
      late ZenithRef ref;
      final node = container.getOrCreateNode<AsyncValue<int>>('n', (r) {
        ref = r;
        return const AsyncData(0);
      });

      final completer1 = Completer<int>();
      final future1 = ref.runAsyncGuarded<int>(
        node,
        () => completer1.future,
        strategy: ConcurrencyStrategy.concurrent,
      );
      final future2 = ref.runAsyncGuarded<int>(
        node,
        () async => 2,
        strategy: ConcurrencyStrategy.concurrent,
      );

      await future2;
      expect((node.value as AsyncData<int>).value, 2);

      // Unlike restartable, the earlier call is allowed to overwrite state.
      completer1.complete(1);
      await future1;
      expect((node.value as AsyncData<int>).value, 1);

      container.dispose();
    });

    test('writes AsyncError when the task throws', () async {
      final container = ZenithContainer();
      late ZenithRef ref;
      final node = container.getOrCreateNode<AsyncValue<int>>('n', (r) {
        ref = r;
        return const AsyncData(0);
      });

      await ref.runAsyncGuarded<int>(
        node,
        () async => throw Exception('boom'),
        strategy: ConcurrencyStrategy.concurrent,
      );

      expect(node.value.hasError, isTrue);

      container.dispose();
    });
  });

  group('ZenithConcurrencyX.runAsyncGuarded — disposal safety', () {
    test('no mutation after disposal mid-flight (restartable)', () async {
      final container = ZenithContainer();
      late ZenithRef ref;
      final node = container.getOrCreateNode<AsyncValue<int>>('n', (r) {
        ref = r;
        return const AsyncData(0);
      });

      final completer = Completer<int>();
      final future = ref.runAsyncGuarded<int>(node, () => completer.future);

      container.dispose();
      completer.complete(1);
      await future;

      expect(ref.isMounted, isFalse);
      expect(node.isDisposed, isTrue);
    });

    test('no mutation after disposal mid-flight (droppable)', () async {
      final container = ZenithContainer();
      late ZenithRef ref;
      final node = container.getOrCreateNode<AsyncValue<int>>('n', (r) {
        ref = r;
        return const AsyncData(0);
      });

      final completer = Completer<int>();
      final future = ref.runAsyncGuarded<int>(
        node,
        () => completer.future,
        strategy: ConcurrencyStrategy.droppable,
      );

      container.dispose();
      completer.complete(1);
      await future;

      expect(ref.isMounted, isFalse);
      expect(node.isDisposed, isTrue);
    });
  });

  group('ZenithIsolateX.runInIsolate', () {
    test('runs computation on a background isolate and writes AsyncData', () async {
      final container = ZenithContainer();
      late ZenithRef ref;
      final node = container.getOrCreateNode<AsyncValue<int>>('n', (r) {
        ref = r;
        return const AsyncData(0);
      });

      await ref.runInIsolate<int, int>(node, 21, _double);

      expect(node.value, isA<AsyncData<int>>());
      expect((node.value as AsyncData<int>).value, 42);

      container.dispose();
    });
  });
}
