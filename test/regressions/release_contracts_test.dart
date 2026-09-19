import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zenith/flutter_zenith.dart';

class AccountId {
  final String id;
  const AccountId(this.id);

  @override
  bool operator ==(Object other) => other is AccountId && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

void main() {
  test('family keys reuse equal arguments and support overrides', () {
    const family = ZenithFamily<String, AccountId>('account');
    final container = ZenithContainer(
      overrides: [
        ZenithOverride(family(const AccountId('a')), (_) => 'override'),
      ],
    );
    addTearDown(container.disposeAsync);
    final first = container.getOrCreate(
      family(const AccountId('a')),
      (_) => 'a',
    );
    final repeated = container.getOrCreate(
      family(AccountId('a')),
      (_) => 'unused',
    );
    final other = container.getOrCreate(
      family(const AccountId('b')),
      (_) => 'b',
    );
    expect(first, same(repeated));
    expect(first.value, 'override');
    expect(other.value, 'b');
    expect(family.registry().key(const AccountId('a')), family(AccountId('a')));
  });

  test('family keys cannot alias manual names or other argument types', () {
    const strings = ZenithFamily<String, String>('profile');
    const integers = ZenithFamily<String, int>('profile');
    final generated = strings('1');
    final manual = ZenithKey<String>('profile#1');
    expect(generated == manual, false);
    expect(manual == generated, false);
    expect(generated == integers(1), false);
    expect(integers(1) == generated, false);
    expect(ZenithKey<num>('count') == ZenithKey<int>('count'), false);
    expect(ZenithKey<int>('count') == ZenithKey<num>('count'), false);
  });

  test(
    'stream cancellation failures reach awaited container disposal',
    () async {
      final container = ZenithContainer();
      final ref = ZenithRef(container);
      final node = ZenithNode<AsyncValue<int>>(const AsyncData(0));
      final failure = StateError('external stream close failed');
      final stream = StreamController<int>(onCancel: () async => throw failure);
      ref.watchStream(node, stream.stream);
      await expectLater(container.disposeAsync(), throwsA(same(failure)));
      await stream.close();
      node.dispose();
    },
  );

  test('failed typed factory awaits registered asynchronous cleanup', () async {
    final container = ZenithContainer();
    final cleanup = Completer<void>();
    var calls = 0;
    expect(
      () => container.getOrCreate(const ZenithKey<int>('bad'), (ref) {
        ref.onDisposeAsync(() {
          calls++;
          return cleanup.future;
        });
        throw StateError('initialization failed');
      }),
      throwsStateError,
    );
    var disposed = false;
    final shutdown = container.disposeAsync().then((_) => disposed = true);
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);
    expect(disposed, false);
    cleanup.complete();
    await shutdown;
    expect(calls, 1);
  });

  test(
    'rate limiter evicts expired requests and retains fresh requests',
    () async {
      final pipeline = ZenithResiliencePipeline().withRateLimiter(
        maxRequests: 1,
        window: const Duration(milliseconds: 100),
      );
      expect(await pipeline.execute(() async => 'first'), 'first');
      await expectLater(
        pipeline.execute(() async => 'blocked'),
        throwsStateError,
      );
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(
        await pipeline.execute(() async => 'after expiry'),
        'after expiry',
      );
      await expectLater(
        pipeline.execute(() async => 'blocked again'),
        throwsStateError,
      );
    },
  );
}
