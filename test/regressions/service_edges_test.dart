import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zenith/flutter_zenith.dart';

class DelayedService extends ZenithService {
  final Completer<void> startGate;
  final bool stopFails;
  int stops = 0;
  bool resourceOpen = false;
  DelayedService(this.startGate, {this.stopFails = false});
  @override
  Future<void> onStart(ZenithRef ref) async {
    await startGate.future;
    resourceOpen = true;
  }

  @override
  Future<void> onStop() async {
    stops++;
    resourceOpen = false;
    if (stopFails) throw StateError('stop failed');
  }
}

void main() {
  test('periodic task failures are observed and timer can run again', () async {
    final container = ZenithContainer();
    final gate = Completer<void>();
    var attempts = 0;
    final service = ZenithPeriodicService(
      interval: const Duration(milliseconds: 1),
      task: (_) async {
        if (++attempts == 1) throw StateError('network');
        if (!gate.isCompleted) gate.complete();
      },
    );
    ZenithRef(container).registerService(service);
    await gate.future;
    await container.disposeAsync();
    expect(attempts, greaterThanOrEqualTo(2));
  });

  test(
    'disposal during startup waits then stops the resource exactly once',
    () async {
      final container = ZenithContainer();
      final gate = Completer<void>();
      final service = DelayedService(gate);
      final registration = ZenithRef(container).registerService(service);
      var disposed = false;
      final completion = container.disposeAsync().then((_) => disposed = true);
      await Future<void>.delayed(Duration.zero);
      expect(disposed, false);
      gate.complete();
      await completion;
      await registration.stopped;
      expect(service.resourceOpen, false);
      expect(service.stops, 1);
      await container.disposeAsync();
      expect(service.stops, 1);
    },
  );

  test(
    'startup failure is observed and exposed even when not awaited immediately',
    () async {
      final container = ZenithContainer();
      final gate = Completer<void>();
      final service = DelayedService(gate);
      final registration = ZenithRef(container).registerService(service);
      gate.completeError(StateError('startup failed'));
      await Future<void>.delayed(Duration.zero);
      expect(registration.lastError, isA<StateError>());
      await expectLater(registration.started, throwsStateError);
      await container.disposeAsync();
      expect(service.stops, 1);
    },
  );

  test('shutdown errors propagate after other services stop', () async {
    final container = ZenithContainer();
    final gate = Completer<void>()..complete();
    final bad = DelayedService(gate, stopFails: true);
    final good = DelayedService(gate);
    final badRegistration = ZenithRef(container).registerService(bad);
    final goodRegistration = ZenithRef(container).registerService(good);
    await Future.wait([badRegistration.started, goodRegistration.started]);
    await expectLater(container.disposeAsync(), throwsStateError);
    expect(good.stops, 1);
    expect(bad.stops, 1);
    await expectLater(badRegistration.stopped, throwsStateError);
  });

  test(
    'periodic tasks do not overlap and shutdown waits for in-flight task',
    () async {
      final container = ZenithContainer();
      final gate = Completer<void>();
      final entered = Completer<void>();
      var calls = 0;
      final service = ZenithPeriodicService(
        interval: const Duration(milliseconds: 1),
        task: (_) async {
          calls++;
          if (!entered.isCompleted) entered.complete();
          await gate.future;
        },
      );
      final registration = ZenithRef(container).registerService(service);
      await registration.started;
      await entered.future;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(calls, 1);
      var stopped = false;
      final shutdown = container.disposeAsync().then((_) => stopped = true);
      await Future<void>.delayed(Duration.zero);
      expect(stopped, false);
      gate.complete();
      await shutdown;
      expect(calls, 1);
    },
  );
}
