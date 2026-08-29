import 'dart:math' as math;

/// A single queued offline mutation waiting to be dispatched.
class OutboxMutation {
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
    required this.tenantId,
    required this.action,
    required this.payload,
    this.maxRetries = 3,
    this.retryCount = 0,
    this.lastError,
    this.lastAttemptedAt,
    this.nextRetryAfter,
  });

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
  final List<OutboxMutation> _queue = [];
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
    _queue.add(OutboxMutation(
      tenantId: tenantId,
      action: action,
      payload: payload,
      maxRetries: maxRetries,
    ));
  }

  /// Sets the currently active (signed-in) tenant.
  ///
  /// Only mutations whose [OutboxMutation.tenantId] matches the active tenant
  /// will be dispatched during [flush].
  void setActiveTenant(String tenantId) {
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
  }) async {
    final active = _activeTenantId;
    if (active == null) return;

    final now = DateTime.now();
    final toFlush = _queue.where((m) => m.tenantId == active).toList();

    for (final mutation in toFlush) {
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
            baseBackoff.inMilliseconds * (1 << math.min(mutation.retryCount - 1, 30));
        final cappedBackoffMs = math.min(rawBackoffMs, maxBackoff.inMilliseconds);
        mutation.nextRetryAfter =
            attemptTime.add(Duration(milliseconds: cappedBackoffMs));

        onMutationError?.call(mutation, e);

        if (mutation.retryCount >= mutation.maxRetries) {
          _queue.remove(mutation);
          _deadLetterQueue.add(mutation);
        }
      }
    }
  }
}
