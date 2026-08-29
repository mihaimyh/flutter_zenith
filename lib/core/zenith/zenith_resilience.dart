import 'dart:async';
import 'dart:math';

import 'async_value.dart';
import 'zenith_container.dart';
import 'zenith_node.dart';

/// Circuit breaker state machine enum.
enum CircuitState {
  /// Normal operation: requests pass through.
  closed,

  /// Circuit is open: requests are immediately rejected without executing task.
  open,

  /// Circuit is probing: next request tests if downstream service has recovered.
  halfOpen,
}

/// A resilience pipeline for retries, circuit breakers, and rate limiters.
///
/// Equivalent to Polly in .NET.
///
/// ```dart
/// final pipeline = ZenithResiliencePipeline()
///   .withRetry(maxAttempts: 3)
///   .withCircuitBreaker(failureThreshold: 5);
///
/// final result = await pipeline.execute(() => api.fetchData());
/// ```
class ZenithResiliencePipeline {
  int? _retryMaxAttempts;
  Duration _retryInitialDelay = const Duration(milliseconds: 100);
  double _retryBackoffFactor = 2.0;
  bool _retryEnableJitter = true;

  int? _circuitThreshold;
  Duration _circuitResetTimeout = const Duration(seconds: 30);
  int _circuitFailureCount = 0;
  DateTime? _circuitOpenedAt;
  CircuitState _circuitState = CircuitState.closed;

  int? _rateLimitMaxRequests;
  Duration _rateLimitWindow = const Duration(seconds: 1);
  final List<DateTime> _requestTimestamps = <DateTime>[];

  final Random _random = Random();

  /// Gets the current circuit breaker state.
  CircuitState get circuitState {
    if (_circuitState == CircuitState.open && _circuitOpenedAt != null) {
      if (DateTime.now().difference(_circuitOpenedAt!) >= _circuitResetTimeout) {
        _circuitState = CircuitState.halfOpen;
      }
    }
    return _circuitState;
  }

  /// Configures a retry strategy with optional exponential backoff and randomized jitter.
  ZenithResiliencePipeline withRetry({
    int maxAttempts = 3,
    Duration initialDelay = const Duration(milliseconds: 100),
    double backoffFactor = 2.0,
    bool enableJitter = true,
  }) {
    _retryMaxAttempts = maxAttempts;
    _retryInitialDelay = initialDelay;
    _retryBackoffFactor = backoffFactor;
    _retryEnableJitter = enableJitter;
    return this;
  }

  /// Configures a circuit breaker strategy that opens after [failureThreshold] failures.
  ZenithResiliencePipeline withCircuitBreaker({
    int failureThreshold = 5,
    Duration resetTimeout = const Duration(seconds: 30),
  }) {
    _circuitThreshold = failureThreshold;
    _circuitResetTimeout = resetTimeout;
    return this;
  }

  /// Configures a sliding window rate limiter strategy.
  ZenithResiliencePipeline withRateLimiter({
    required int maxRequests,
    required Duration window,
  }) {
    _rateLimitMaxRequests = maxRequests;
    _rateLimitWindow = window;
    return this;
  }

  /// Executes [task] protected by this resilience pipeline.
  Future<T> execute<T>(Future<T> Function() task) async {
    // 1. Check Circuit Breaker State
    if (_circuitThreshold != null) {
      final state = circuitState;
      if (state == CircuitState.open) {
        throw StateError(
          'ZenithResiliencePipeline: Circuit breaker is OPEN. Execution rejected.',
        );
      }
    }

    // 2. Check Rate Limiter
    if (_rateLimitMaxRequests != null) {
      final now = DateTime.now();
      _requestTimestamps.removeWhere(
        (t) => now.difference(t) > _rateLimitWindow,
      );

      if (_requestTimestamps.length >= _rateLimitMaxRequests!) {
        throw StateError(
          'ZenithResiliencePipeline: Rate limit exceeded ($_rateLimitMaxRequests requests per $_rateLimitWindow). Execution rejected.',
        );
      }
      _requestTimestamps.add(now);
    }

    // 3. Execute with Retry
    final maxAttempts = _retryMaxAttempts ?? 1;
    var currentAttempt = 0;
    var currentDelay = _retryInitialDelay;

    while (currentAttempt < maxAttempts) {
      currentAttempt++;
      try {
        final result = await task();

        // Successful call resets circuit breaker
        if (_circuitThreshold != null) {
          _circuitFailureCount = 0;
          _circuitOpenedAt = null;
          _circuitState = CircuitState.closed;
        }

        return result;
      } catch (error) {
        // Record Circuit Breaker failure
        if (_circuitThreshold != null) {
          _circuitFailureCount++;
          if (_circuitFailureCount >= _circuitThreshold!) {
            _circuitState = CircuitState.open;
            _circuitOpenedAt = DateTime.now();
          }
        }

        if (currentAttempt >= maxAttempts) {
          rethrow;
        }

        // Apply delay with backoff and jitter
        var delayMs = currentDelay.inMilliseconds.toDouble();
        if (_retryEnableJitter) {
          // Add 0-50% randomized jitter to prevent thundering herd spikes
          delayMs += delayMs * (_random.nextDouble() * 0.5);
        }

        await Future<void>.delayed(Duration(milliseconds: delayMs.toInt()));
        currentDelay = Duration(
          milliseconds: (currentDelay.inMilliseconds * _retryBackoffFactor).toInt(),
        );
      }
    }

    throw StateError('Unreachable');
  }
}

/// Extension on [ZenithRef] providing resilient execution.
extension ZenithResilienceRefX on ZenithRef {
  /// Runs [task] protected by [pipeline] and writes the state to [node].
  Future<void> runResilient<T>(
    ZenithNode<AsyncValue<T>> node,
    Future<T> Function() task, {
    required ZenithResiliencePipeline pipeline,
  }) async {
    return runAsync(node, () => pipeline.execute(task));
  }
}
