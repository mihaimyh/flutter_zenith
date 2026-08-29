import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zenith/flutter_zenith.dart';

void main() {
  group('AsyncValue equality', () {
    test('AsyncData with same value are equal', () {
      expect(const AsyncData<int>(42), equals(const AsyncData<int>(42)));
      expect(const AsyncData<int>(42).hashCode, const AsyncData<int>(42).hashCode);
    });

    test('AsyncData with different values are not equal', () {
      expect(const AsyncData<int>(42), isNot(equals(const AsyncData<int>(99))));
    });

    test('AsyncData and AsyncLoading are not equal', () {
      expect(const AsyncData<int>(42), isNot(equals(const AsyncLoading<int>(42))));
    });

    test('AsyncLoading with same previousData are equal', () {
      expect(
        const AsyncLoading<int>(42),
        equals(const AsyncLoading<int>(42)),
      );
      expect(
        const AsyncLoading<int>(42).hashCode,
        const AsyncLoading<int>(42).hashCode,
      );
    });

    test('AsyncLoading with null previousData are equal', () {
      expect(
        const AsyncLoading<int>(),
        equals(const AsyncLoading<int>()),
      );
    });

    test('AsyncError with same error are equal', () {
      final error = Exception('boom');
      final st = StackTrace.current;
      expect(
        AsyncError<int>(error, st),
        equals(AsyncError<int>(error, StackTrace.empty)),
      );
    });

    test('AsyncError with different errors are not equal', () {
      final st = StackTrace.current;
      expect(
        AsyncError<int>(Exception('a'), st),
        isNot(equals(AsyncError<int>(Exception('b'), st))),
      );
    });

    test('ZenithNode.set() skips notification for equal AsyncData', () {
      final node = ZenithNode<AsyncValue<int>>(const AsyncData<int>(42));
      var notifyCount = 0;
      node.subscribe(_CountingSubscriber(() => notifyCount++));

      // Setting the same value again should be a no-op.
      node.set(const AsyncData<int>(42));
      expect(notifyCount, 0);

      // Setting a different value should notify.
      node.set(const AsyncData<int>(99));
      expect(notifyCount, 1);
    });
  });

  group('AsyncValue convenience methods', () {
    test('hasData returns true for AsyncData', () {
      expect(const AsyncData<int>(42).hasData, isTrue);
      expect(const AsyncLoading<int>().hasData, isFalse);
      expect(AsyncError<int>(Exception(''), StackTrace.empty).hasData, isFalse);
    });

    test('requireValue returns value for AsyncData', () {
      expect(const AsyncData<int>(42).requireValue, 42);
    });

    test('requireValue throws for non-data states', () {
      expect(() => const AsyncLoading<int>().requireValue, throwsStateError);
      expect(
        () => AsyncError<int>(Exception(''), StackTrace.empty).requireValue,
        throwsStateError,
      );
    });

    test('maybeWhen dispatches to matched branch or orElse', () {
      const AsyncValue<int> data = AsyncData<int>(42);
      const AsyncValue<int> loading = AsyncLoading<int>();

      final dataResult = data.maybeWhen(
        data: (v) => 'data:$v',
        orElse: () => 'fallback',
      );
      expect(dataResult, 'data:42');

      final loadingResult = loading.maybeWhen(
        data: (v) => 'data:$v',
        orElse: () => 'fallback',
      );
      expect(loadingResult, 'fallback');
    });

    test('whenOrNull returns null for unhandled states', () {
      const AsyncValue<int> loading = AsyncLoading<int>();

      final result = loading.whenOrNull<String>(
        data: (v) => 'data:$v',
      );
      expect(result, isNull);

      const AsyncValue<int> data = AsyncData<int>(42);
      final dataResult = data.whenOrNull<String>(
        data: (v) => 'data:$v',
      );
      expect(dataResult, 'data:42');
    });

    test('toString produces readable output', () {
      expect(const AsyncData<int>(42).toString(), 'AsyncData<int>(42)');
      expect(const AsyncLoading<int>(1).toString(), 'AsyncLoading<int>(1)');
      expect(
        AsyncError<int>(Exception('boom'), StackTrace.empty).toString(),
        contains('AsyncError<int>'),
      );
    });
  });
}

class _CountingSubscriber implements ZenithSubscriber {
  final void Function() onNotify;
  _CountingSubscriber(this.onNotify);

  @override
  void onNodeChanged(ZenithNode<dynamic> node) => onNotify();
}
