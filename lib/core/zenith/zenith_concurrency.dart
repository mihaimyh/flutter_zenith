import 'dart:isolate';

import 'async_value.dart';
import 'zenith_container.dart';
import 'zenith_node.dart';

/// Tracks the current "generation" (execution token) per [ZenithNode] so
/// [ZenithConcurrencyX.runAsyncGuarded] can detect and drop stale results
/// under [ConcurrencyStrategy.restartable]. Keyed by node identity so no
/// extra fields are needed on [ZenithNode] or [ZenithRef].
final Expando<int> _zenithTaskGeneration = Expando<int>();

/// Strategies for handling back-to-back async calls that write to the same
/// [ZenithNode].
enum ConcurrencyStrategy {
  /// Allows concurrent runs. Whichever call completes last wins (matches the
  /// existing [ZenithRef.runAsync] behavior).
  concurrent,

  /// Ignores any new calls while a task is actively loading (e.g. prevents
  /// double-submitting a form on rapid taps).
  droppable,

  /// Invalidates previous pending calls so only the latest execution is
  /// allowed to update state (e.g. search-as-you-type autocomplete).
  restartable,
}

/// Adds concurrency-guarded async execution to [ZenithRef].
extension ZenithConcurrencyX on ZenithRef {
  /// Executes [task] and writes its result to [node], guarding against
  /// race conditions between overlapping calls according to [strategy].
  ///
  /// - [ConcurrencyStrategy.droppable]: if [node] is currently
  ///   [AsyncValue.isLoading], this call is a no-op.
  /// - [ConcurrencyStrategy.restartable]: if a newer call to this method
  ///   (for the same [node]) starts before [task] resolves, this call's
  ///   result is silently discarded.
  /// - [ConcurrencyStrategy.concurrent]: no guarding; behaves like
  ///   [ZenithRef.runAsync].
  ///
  /// Every state mutation is also guarded by [ZenithRef.isMounted].
  Future<void> runAsyncGuarded<T>(
    ZenithNode<AsyncValue<T>> node,
    Future<T> Function() task, {
    ConcurrencyStrategy strategy = ConcurrencyStrategy.restartable,
  }) async {
    if (!isMounted) return;

    if (strategy == ConcurrencyStrategy.droppable && node.value.isLoading) {
      return;
    }

    final generation = (_zenithTaskGeneration[node] ?? 0) + 1;
    _zenithTaskGeneration[node] = generation;

    bool isCurrent() =>
        strategy != ConcurrencyStrategy.restartable ||
        _zenithTaskGeneration[node] == generation;

    set<AsyncValue<T>>(node, AsyncLoading<T>(node.value.valueOrNull));

    try {
      final data = await task();
      if (!isMounted || !isCurrent()) return;
      set<AsyncValue<T>>(node, AsyncData<T>(data));
    } catch (error, stackTrace) {
      if (!isMounted || !isCurrent()) return;
      set<AsyncValue<T>>(node, AsyncError<T>(error, stackTrace));
    }
  }
}

/// Adds background-isolate execution to [ZenithRef].
extension ZenithIsolateX on ZenithRef {
  /// Runs [heavyComputation] on a background [Isolate] via [Isolate.run],
  /// then writes the result to [node] via [runAsyncGuarded].
  ///
  /// Keeps the UI thread free of jank for expensive synchronous work (JSON
  /// parsing, crypto, data transforms). [heavyComputation] and [payload]
  /// must be safe to send across an isolate boundary -- do not close over a
  /// [ZenithRef], `BuildContext`, or other non-sendable, mutable state.
  Future<void> runInIsolate<T, P>(
    ZenithNode<AsyncValue<T>> node,
    P payload,
    T Function(P payload) heavyComputation, {
    ConcurrencyStrategy strategy = ConcurrencyStrategy.concurrent,
  }) {
    return runAsyncGuarded<T>(
      node,
      () => Isolate.run(() => heavyComputation(payload)),
      strategy: strategy,
    );
  }
}
