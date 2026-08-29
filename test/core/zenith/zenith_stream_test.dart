import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zenith/flutter_zenith.dart';

void main() {
  group('ZenithStreamX.watchStream', () {
    test('maps stream events to AsyncData and errors to AsyncError', () async {
      final container = ZenithContainer();
      late ZenithRef ref;
      final node = container.getOrCreateNode<AsyncValue<int>>('n', (r) {
        ref = r;
        return const AsyncData<int>(0);
      });

      final controller = StreamController<int>();
      ref.watchStream(node, controller.stream);

      // Initial state should be AsyncLoading with previous data preserved.
      expect(node.value.isLoading, isTrue);
      expect(node.value.valueOrNull, 0);

      controller.add(1);
      await Future<void>.delayed(Duration.zero);
      expect(node.value, isA<AsyncData<int>>());
      expect((node.value as AsyncData<int>).value, 1);

      controller.add(2);
      await Future<void>.delayed(Duration.zero);
      expect((node.value as AsyncData<int>).value, 2);

      controller.addError(Exception('boom'));
      await Future<void>.delayed(Duration.zero);
      expect(node.value.hasError, isTrue);

      await controller.close();
      container.dispose();
    });

    test('auto-cancels subscription on container disposal', () async {
      final container = ZenithContainer();
      late ZenithRef ref;
      final node = container.getOrCreateNode<AsyncValue<int>>('n', (r) {
        ref = r;
        return const AsyncData<int>(0);
      });

      final controller = StreamController<int>();
      ref.watchStream(node, controller.stream);

      container.dispose();

      // Adding events after disposal should not throw or mutate state.
      controller.add(999);
      await Future<void>.delayed(Duration.zero);
      expect(node.isDisposed, isTrue);

      await controller.close();
    });

    test('watchStream is a no-op when ref is already disposed', () async {
      final container = ZenithContainer();
      late ZenithRef ref;
      final node = container.getOrCreateNode<AsyncValue<int>>('n', (r) {
        ref = r;
        return const AsyncData<int>(0);
      });

      container.dispose();

      final controller = StreamController<int>();

      // Should not throw and should not modify node state.
      ref.watchStream(node, controller.stream);

      // The node is already disposed, so no mutation should have happened.
      expect(node.isDisposed, isTrue);
      expect(ref.isMounted, isFalse);

      await controller.close();
    });
  });

  group('StreamNodeX.watch', () {
    test('delegates to ref.watchStream', () async {
      final container = ZenithContainer();
      late ZenithRef ref;
      final node = container.getOrCreateNode<AsyncValue<String>>('n', (r) {
        ref = r;
        return const AsyncLoading<String>();
      });

      final controller = StreamController<String>();
      node.watch(ref, controller.stream);

      controller.add('hello');
      await Future<void>.delayed(Duration.zero);
      expect((node.value as AsyncData<String>).value, 'hello');

      await controller.close();
      container.dispose();
    });
  });
}
