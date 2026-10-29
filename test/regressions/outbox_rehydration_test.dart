import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zenith/zenith_identity.dart';

void main() {
  group('ZenithOutboxEngine rehydration', () {
    test('re-enqueueing a persisted id does not double-dispatch', () async {
      final engine = ZenithOutboxEngine()..setActiveTenant('a');

      expect(
        engine.enqueue(
          id: 'm1',
          tenantId: 'a',
          action: 'trackXp',
          payload: {'k': 1},
        ),
        isTrue,
      );

      await engine.flush((m) async => throw StateError('offline'));
      engine.setActiveTenant(null);
      engine.setActiveTenant('a');

      expect(
        engine.enqueue(
          id: 'm1',
          tenantId: 'a',
          action: 'trackXp',
          payload: {'k': 1},
        ),
        isFalse,
        reason: 'rehydrated row is the same logical mutation',
      );
      expect(engine.pendingCount('a'), 1);

      var calls = 0;
      await engine.flush((m) async => calls++, ignoreBackoff: true);
      expect(calls, 1);
      expect(engine.pendingCount('a'), 0);
    });

    test(
      'clearTenant drops pending work so rehydration cannot duplicate it',
      () async {
        final engine = ZenithOutboxEngine()..setActiveTenant('a');
        engine.enqueue(tenantId: 'a', action: 'x', payload: {'k': 1});
        engine.enqueue(tenantId: 'b', action: 'y', payload: {});

        await engine.flush((m) async => throw StateError('offline'));
        engine.setActiveTenant(null);

        expect(engine.clearTenant('a'), 1);
        expect(engine.pendingCount('a'), 0);
        expect(engine.pendingCount('b'), 1);

        engine.setActiveTenant('a');
        engine.enqueue(tenantId: 'a', action: 'x', payload: {'k': 1});

        var calls = 0;
        await engine.flush((m) async => calls++, ignoreBackoff: true);
        expect(calls, 1);
      },
    );

    test(
      'remove drops a single pending mutation and aborts its dispatch',
      () async {
        final engine = ZenithOutboxEngine()..setActiveTenant('a');
        engine.enqueue(id: 'm1', tenantId: 'a', action: 'first', payload: {});
        engine.enqueue(id: 'm2', tenantId: 'a', action: 'second', payload: {});

        var calls = 0;
        await engine.flush((m) async {
          calls++;
          engine.remove('m2');
        });

        expect(calls, 1);
        expect(engine.pendingCount('a'), 0);
        expect(engine.remove('m2'), isFalse);
      },
    );

    test('restored retry state dead-letters a poison mutation', () async {
      final engine = ZenithOutboxEngine()..setActiveTenant('a');
      engine.enqueue(
        id: 'poison',
        tenantId: 'a',
        action: 'x',
        payload: {},
        retryCount: 2,
        lastError: 'boom',
      );

      final attempts = <int>[];
      await engine.flush((m) async {
        attempts.add(m.retryCount);
        throw StateError('poison');
      });

      expect(attempts, [2], reason: 'retry counter survives the restart');
      expect(engine.pendingCount('a'), 0);
      expect(engine.deadLetterCount('a'), 1);
      expect(engine.deadLetterQueue.single.retryCount, 3);
    });

    test(
      'restored nextRetryAfter prevents a post-restart retry burst',
      () async {
        final engine = ZenithOutboxEngine()..setActiveTenant('a');
        engine.enqueue(
          id: 'm1',
          tenantId: 'a',
          action: 'x',
          payload: {},
          retryCount: 1,
          nextRetryAfter: DateTime.now().add(const Duration(milliseconds: 400)),
        );

        var calls = 0;
        await engine.flush((m) async => calls++);

        expect(calls, 0);
        expect(engine.pendingCount('a'), 1);
      },
    );

    test('a fully exhausted mutation is dead-lettered at enqueue', () {
      final engine = ZenithOutboxEngine();
      expect(
        engine.enqueue(
          id: 'm1',
          tenantId: 'a',
          action: 'x',
          payload: {},
          retryCount: 3,
        ),
        isTrue,
      );
      expect(engine.pendingCount('a'), 0);
      expect(engine.deadLetterCount('a'), 1);
      expect(
        engine.enqueue(id: 'm1', tenantId: 'a', action: 'x', payload: {}),
        isFalse,
      );
    });
  });
}
