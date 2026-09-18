import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

/// A single queued offline mutation waiting to be dispatched.
class OutboxMutation {
  static final _random = math.Random.secure();

  /// Stable idempotency key. Send this with every retry to a supporting server.
  final String id;

  static String _newId() => List.generate(
    16,
    (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();

  /// The tenant that owns this mutation.
  final String tenantId;

  /// The action name (e.g. 'UpdateBio', 'CreatePost').
  final String action;

  /// The mutation payload.
  final Map<String, dynamic> payload;

  /// Maximum retry attempts before moving to dead-letter queue.
  final int maxRetries;

  /// Number of failed dispatch attempts.
  int retryCount;

  /// The last error caught during dispatch.
  Object? lastError;

  /// Timestamp of the last dispatch attempt.
  DateTime? lastAttemptedAt;

  /// Earliest timestamp at which this mutation is eligible to be retried.
  DateTime? nextRetryAfter;

  /// Creates an [OutboxMutation].
  OutboxMutation({
    String? id,
    required this.tenantId,
    required this.action,
    required this.payload,
    this.maxRetries = 3,
    this.retryCount = 0,
    this.lastError,
    this.lastAttemptedAt,
    this.nextRetryAfter,
  }) : id = id ?? _newId();

  /// Whether this mutation has waited out its backoff duration and is ready
  /// to be dispatched again.
  ///
  /// Includes resilience against clock anomalies / reverse time-jumps.
  bool isEligibleForRetry([DateTime? now]) {
    final target = nextRetryAfter;
    if (target == null) return true;
    final current = now ?? DateTime.now();

    // If clock drift causes target to appear in the distant future (> 2 minutes),
    // treat the backoff as elapsed to prevent indefinitely frozen mutations.
    if (target.difference(current).inMinutes > 2) {
      return true;
    }

    return !current.isBefore(target);
  }
}

/// An offline mutation queue that ensures a signed-out tenant's queued writes
/// cannot be dispatched under another user's session, with error resilience,
/// capped exponential backoff windows, clock-drift guards, and dead-letter
/// queue isolation.
///
/// Usage:
/// ```dart
/// outbox.enqueue(tenantId: 'user_a', action: 'UpdateBio', payload: {});
/// outbox.setActiveTenant('user_b');
/// await outbox.flush(dispatch); // user_a's mutation is NOT flushed
/// ```
class ZenithOutboxEngine {
  final _queue = LinkedHashSet<OutboxMutation>.identity();
  Future<void>? _flushFuture;
  int _generation = 0;
  final List<OutboxMutation> _deadLetterQueue = [];
  String? _activeTenantId;

  /// Unmodifiable view of dead-lettered mutations.
  List<OutboxMutation> get deadLetterQueue =>
      List.unmodifiable(_deadLetterQueue);

  /// Enqueues a mutation for [tenantId].
  void enqueue({
    required String tenantId,
    required String action,
    required Map<String, dynamic> payload,
    int maxRetries = 3,
  }) {
    _queue.add(
      OutboxMutation(
        tenantId: tenantId,
        action: action,
        payload: payload,
        maxRetries: maxRetries,
      ),
    );
  }

  /// Sets the active tenant, or null on sign-out. Invalidates any pending pass.
  ///
  /// Only mutations whose [OutboxMutation.tenantId] matches the active tenant
  /// will be dispatched during [flush].
  void setActiveTenant(String? tenantId) {
    _generation++;
    _activeTenantId = tenantId;
  }

  /// Returns the number of pending (unflushed) mutations for [tenantId].
  int pendingCount(String tenantId) =>
      _queue.where((m) => m.tenantId == tenantId).length;

  /// Returns the number of dead-letter mutations for [tenantId].
  int deadLetterCount(String tenantId) =>
      _deadLetterQueue.where((m) => m.tenantId == tenantId).length;

  /// Dispatches all pending mutations for the **active tenant** via [dispatcher].
  ///
  /// Mutations belonging to inactive (signed-out) tenants are left in the
  /// queue — they will be dispatched when their tenant is next set active.
  ///
  /// Concurrent callers share the active pass; enqueues during a pass wait for
  /// the next flush. Bind the dispatcher to immutable tenant credentials before
  /// calling this method. Already sent requests cannot be recalled on sign-out.
  /// Error-observer exceptions are reported after queue bookkeeping completes.
  ///
  /// Individual mutation errors do **not** abort the entire flush pass:
  /// - The failed mutation increments its retry count and sets an exponential
  ///   backoff [OutboxMutation.nextRetryAfter] timestamp, capped at [maxBackoff].
  /// - Mutations that have not reached their backoff window are skipped.
  /// - If the retry threshold is reached, it is moved to the dead-letter queue.
  /// - Subsequent mutations continue processing to avoid head-of-line blocking.
  Future<void> flush(
    Future<void> Function(OutboxMutation mutation) dispatcher, {
    void Function(OutboxMutation mutation, Object error)? onMutationError,
    bool ignoreBackoff = false,
    Duration baseBackoff = const Duration(milliseconds: 100),
    Duration maxBackoff = const Duration(seconds: 60),
  }) {
    final running = _flushFuture;
    if (running != null) return running;
    final completion = Completer<void>();
    _flushFuture = completion.future;
    _flush(
      dispatcher,
      onMutationError: onMutationError,
      ignoreBackoff: ignoreBackoff,
      baseBackoff: baseBackoff,
      maxBackoff: maxBackoff,
    ).then(
      (_) {
        _flushFuture = null;
        completion.complete();
      },
      onError: (Object error, StackTrace stack) {
        _flushFuture = null;
        completion.completeError(error, stack);
      },
    );
    return completion.future;
  }

  Future<void> _flush(
    Future<void> Function(OutboxMutation) dispatcher, {
    void Function(OutboxMutation, Object)? onMutationError,
    required bool ignoreBackoff,
    required Duration baseBackoff,
    required Duration maxBackoff,
  }) async {
    final generation = _generation;
    Object? observerError;
    StackTrace? observerStack;
    final active = _activeTenantId;
    if (active == null) return;

    final now = DateTime.now();
    final toFlush = _queue.where((m) => m.tenantId == active).toList();

    for (final mutation in toFlush) {
      if (generation != _generation) break;
      if (!ignoreBackoff && !mutation.isEligibleForRetry(now)) {
        continue;
      }

      try {
        await dispatcher(mutation);
        _queue.remove(mutation);
      } catch (e) {
        mutation.retryCount++;
        mutation.lastError = e;
        final attemptTime = DateTime.now();
        mutation.lastAttemptedAt = attemptTime;

        final rawBackoffMs =
            baseBackoff.inMilliseconds *
            (1 << math.min(mutation.retryCount - 1, 30));
        final cappedBackoffMs = math.min(
          rawBackoffMs,
          maxBackoff.inMilliseconds,
        );
        mutation.nextRetryAfter = attemptTime.add(
          Duration(milliseconds: cappedBackoffMs),
        );

        if (mutation.retryCount >= mutation.maxRetries) {
          _queue.remove(mutation);
          _deadLetterQueue.add(mutation);
        }
        try {
          onMutationError?.call(mutation, e);
        } catch (error, stack) {
          observerError ??= error;
          observerStack ??= stack;
        }
      }
    }
    if (observerError != null) {
      Error.throwWithStackTrace(observerError, observerStack!);
    }
  }
}
