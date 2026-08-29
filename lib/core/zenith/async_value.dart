import 'package:flutter/foundation.dart';

import 'zenith_container.dart';
import 'zenith_node.dart';

/// A sealed union representing the state of an asynchronous operation.
///
/// Every async workflow transitions through these states:
/// - [AsyncLoading] — the operation is in progress (optionally carries
///   the previous successful value for optimistic UI).
/// - [AsyncData] — the operation completed successfully with a [T] result.
/// - [AsyncError] — the operation failed with an [error] and [stackTrace].
///
/// Use [when] for exhaustive pattern matching, or the convenience getters
/// [isLoading], [hasData], [hasError], [valueOrNull], and [requireValue]
/// for quick checks.
@immutable
sealed class AsyncValue<T> {
  /// Creates an [AsyncValue].
  const AsyncValue();

  /// Exhaustively pattern-matches all three async states.
  ///
  /// Every branch must be provided. For partial matching, see [maybeWhen]
  /// or [whenOrNull].
  R when<R>({
    required R Function(T data) data,
    required R Function(T? previousData) loading,
    required R Function(Object error, StackTrace stackTrace) error,
  }) {
    final onData = data;
    final onLoading = loading;
    final onError = error;

    return switch (this) {
      AsyncData<T>(:final value) => onData(value),
      AsyncLoading<T>(:final previousData) => onLoading(previousData),
      AsyncError<T>(:final error, :final stackTrace) => onError(
        error,
        stackTrace,
      ),
    };
  }

  /// Pattern-matches with an [orElse] fallback for unhandled states.
  ///
  /// Provide only the branches you care about; unhandled states fall
  /// through to [orElse].
  R maybeWhen<R>({
    R Function(T data)? data,
    R Function(T? previousData)? loading,
    R Function(Object error, StackTrace stackTrace)? error,
    required R Function() orElse,
  }) {
    return switch (this) {
      AsyncData<T>(:final value) => data != null ? data(value) : orElse(),
      AsyncLoading<T>(:final previousData) =>
        loading != null ? loading(previousData) : orElse(),
      AsyncError<T>(error: final err, stackTrace: final st) =>
        error != null ? error(err, st) : orElse(),
    };
  }

  /// Pattern-matches and returns `null` for unhandled states.
  ///
  /// A shorthand for [maybeWhen] where the fallback is always `null`.
  R? whenOrNull<R>({
    R Function(T data)? data,
    R Function(T? previousData)? loading,
    R Function(Object error, StackTrace stackTrace)? error,
  }) {
    return switch (this) {
      AsyncData<T>(:final value) => data?.call(value),
      AsyncLoading<T>(:final previousData) => loading?.call(previousData),
      AsyncError<T>(error: final err, stackTrace: final st) =>
        error?.call(err, st),
    };
  }

  /// The most recent successful value, or `null` if no data has arrived yet.
  ///
  /// During [AsyncLoading], returns the [AsyncLoading.previousData] if
  /// available. During [AsyncError], returns `null`.
  T? get valueOrNull => switch (this) {
    AsyncData<T>(:final value) => value,
    AsyncLoading<T>(:final previousData) => previousData,
    _ => null,
  };

  /// Returns the current value, throwing a [StateError] if no data is
  /// available.
  ///
  /// Use this only when you are certain the value exists (e.g. after
  /// verifying [hasData]).
  T get requireValue {
    return switch (this) {
      AsyncData<T>(:final value) => value,
      _ => throw StateError(
        'Cannot get value from $runtimeType — '
        'AsyncValue is not AsyncData.',
      ),
    };
  }

  /// Whether this value is currently loading.
  bool get isLoading => this is AsyncLoading<T>;

  /// Whether this value holds successful data.
  bool get hasData => this is AsyncData<T>;

  /// Whether this value represents a failed operation.
  bool get hasError => this is AsyncError<T>;
}

/// The successful state of an [AsyncValue], holding the result [value].
class AsyncData<T> extends AsyncValue<T> {
  /// The successfully loaded value.
  final T value;

  /// Creates an [AsyncData] with the given [value].
  const AsyncData(this.value);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AsyncData<T> && other.value == value);

  @override
  int get hashCode => Object.hash(runtimeType, value);

  @override
  String toString() => 'AsyncData<$T>($value)';
}

/// The loading state of an [AsyncValue].
///
/// Optionally carries the [previousData] from the last successful load,
/// enabling optimistic UI patterns (e.g. showing stale data with a
/// loading indicator).
class AsyncLoading<T> extends AsyncValue<T> {
  /// The data value from the previous successful load, if any.
  final T? previousData;

  /// Creates an [AsyncLoading], optionally preserving [previousData].
  const AsyncLoading([this.previousData]);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AsyncLoading<T> && other.previousData == previousData);

  @override
  int get hashCode => Object.hash(runtimeType, previousData);

  @override
  String toString() => 'AsyncLoading<$T>($previousData)';
}

/// The error state of an [AsyncValue], holding the [error] and [stackTrace].
class AsyncError<T> extends AsyncValue<T> {
  /// The error object from the failed operation.
  final Object error;

  /// The stack trace captured at the point of failure.
  final StackTrace stackTrace;

  /// Creates an [AsyncError] with the given [error] and [stackTrace].
  const AsyncError(this.error, this.stackTrace);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AsyncError<T> && other.error == error);

  @override
  int get hashCode => Object.hash(runtimeType, error);

  @override
  String toString() => 'AsyncError<$T>($error)';
}

/// Adds mounted-safe async execution helpers directly on async state nodes.
extension SafeAsyncNodeX<T> on ZenithNode<AsyncValue<T>> {
  /// Executes [future] and writes its result to this node, guarding every
  /// mutation with [ref]'s lifecycle. Equivalent to `ref.runAsync(this, future)`.
  Future<void> guard(ZenithRef ref, Future<T> Function() future) {
    return ref.runAsync(this, future);
  }
}
