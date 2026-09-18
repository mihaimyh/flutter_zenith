import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zenith/zenith_identity.dart';

void main() {
  ZenithOutboxEngine queue() => ZenithOutboxEngine()..setActiveTenant('a');
  void add(ZenithOutboxEngine box, String action) =>
      box.enqueue(tenantId: 'a', action: action, payload: {});

  for (final backToSameTenant in [false, true]) {
    test(
      'sign-out ${backToSameTenant ? 'and return' : ''} invalidates a pending flush',
      () async {
        final box = queue();
        add(box, 'first');
        add(box, 'second');
        final gate = Completer<void>();
        final calls = <String>[];
        final pending = box.flush((m) async {
          calls.add(m.action);
          await gate.future;
        });
        box.setActiveTenant(null);
        if (backToSameTenant) box.setActiveTenant('a');
        gate.complete();
        await pending;
        expect(calls, ['first']);
        expect(box.pendingCount('a'), 1);
      },
    );
  }

  test(
    'enqueue during flush is retained and processed on the next pass',
    () async {
      final box = queue();
      add(box, 'first');
      await box.flush((_) async {
        add(box, 'second');
      });
      expect(box.pendingCount('a'), 1);
      final calls = <String>[];
      await box.flush((m) async {
        calls.add(m.action);
      });
      expect(calls, ['second']);
    },
  );

  test('concurrent callers share completion and failure bookkeeping', () async {
    final box = queue();
    add(box, 'first');
    final gate = Completer<void>();
    var calls = 0;
    Future<void> dispatch(OutboxMutation m) async {
      calls++;
      await gate.future;
    }

    final first = box.flush(dispatch);
    final second = box.flush(dispatch);
    expect(identical(first, second), true);
    gate.completeError(StateError('network'));
    await Future.wait([first, second]);
    expect(calls, 1);
    expect(box.pendingCount('a'), 1);
    final attempts = <int>[];
    await box.flush((m) async {
      attempts.add(m.retryCount);
    }, ignoreBackoff: true);
    expect(attempts, [1]);
  });

  test(
    'retry keeps mutation ID and error callback cannot lose queue entries',
    () async {
      final box = queue();
      add(box, 'first');
      add(box, 'second');
      final ids = <String>[];
      await expectLater(
        box.flush((m) async {
          if (m.action == 'first') {
            ids.add(m.id);
            throw StateError('network');
          }
        }, onMutationError: (_, _) => throw StateError('observer')),
        throwsStateError,
      );
      expect(box.pendingCount('a'), 1);
      await box.flush((m) async {
        ids.add(m.id);
      }, ignoreBackoff: true);
      expect(ids[0], ids[1]);
      expect(box.pendingCount('a'), 0);
    },
  );

  test(
    'large batches preserve order, inactive entries and exact dispatch count',
    () async {
      final box = queue();
      box.enqueue(tenantId: 'b', action: 'inactive', payload: {});
      for (var i = 0; i < 10000; i++) {
        add(box, '$i');
      }
      var index = 0;
      await box.flush((m) async {
        expect(m.action, '${index++}');
      });
      expect(index, 10000);
      expect(box.pendingCount('a'), 0);
      expect(box.pendingCount('b'), 1);
    },
  );
}
