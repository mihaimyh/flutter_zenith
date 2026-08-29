import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zenith/flutter_zenith.dart';

void main() {
  group('ZenithResiliencePipeline Retry Strategy', () {
    test('retries failed execution up to maxAttempts', () async {
      final pipeline = ZenithResiliencePipeline().withRetry(
        maxAttempts: 3,
        initialDelay: const Duration(milliseconds: 5),
        enableJitter: false,
      );

      var attempts = 0;
      final result = await pipeline.execute(() async {
        attempts++;
        if (attempts < 3) {
          throw Exception('Transient failure');
        }
        return 'success';
      });

      expect(result, 'success');
      expect(attempts, 3);
    });

    test('rethrows error after exhausting maxAttempts', () async {
      final pipeline = ZenithResiliencePipeline().withRetry(
        maxAttempts: 2,
        initialDelay: const Duration(milliseconds: 5),
        enableJitter: false,
      );

      var attempts = 0;
      expect(
        () => pipeline.execute(() async {
          attempts++;
          throw Exception('Persistent failure');
        }),
        throwsA(isA<Exception>()),
      );

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(attempts, 2);
    });
  });

  group('ZenithResiliencePipeline CircuitBreaker Strategy', () {
    test('opens circuit when failureThreshold is reached and rejects requests', () async {
      final pipeline = ZenithResiliencePipeline().withCircuitBreaker(
        failureThreshold: 2,
        resetTimeout: const Duration(milliseconds: 50),
      );

      expect(pipeline.circuitState, CircuitState.closed);

      // Failure 1
      try {
        await pipeline.execute(() async => throw Exception('err1'));
      } catch (_) {}

      expect(pipeline.circuitState, CircuitState.closed);

      // Failure 2 (reaches threshold of 2)
      try {
        await pipeline.execute(() async => throw Exception('err2'));
      } catch (_) {}

      // Circuit is now OPEN
      expect(pipeline.circuitState, CircuitState.open);

      // Next call is immediately rejected without running task
      var taskRan = false;
      expect(
        () => pipeline.execute(() async {
          taskRan = true;
          return 'ok';
        }),
        throwsStateError,
      );
      expect(taskRan, isFalse);

      // Wait for resetTimeout to pass -> halfOpen
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(pipeline.circuitState, CircuitState.halfOpen);

      // Successful call resets circuit back to closed
      final res = await pipeline.execute(() async => 'recovered');
      expect(res, 'recovered');
      expect(pipeline.circuitState, CircuitState.closed);
    });
  });

  group('ZenithResiliencePipeline RateLimiter Strategy', () {
    test('rejects requests exceeding rate limit in window', () async {
      final pipeline = ZenithResiliencePipeline().withRateLimiter(
        maxRequests: 2,
        window: const Duration(milliseconds: 100),
      );

      final r1 = await pipeline.execute(() async => 'req1');
      final r2 = await pipeline.execute(() async => 'req2');

      expect(r1, 'req1');
      expect(r2, 'req2');

      // 3rd request exceeds limit of 2 in 100ms window
      expect(
        () => pipeline.execute(() async => 'req3'),
        throwsStateError,
      );
    });
  });
}
