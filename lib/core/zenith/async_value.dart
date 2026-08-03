import 'package:flutter/foundation.dart';

import 'zenith_container.dart';
import 'zenith_node.dart';

@immutable
sealed class AsyncValue<T> {
  const AsyncValue();

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

  T? get valueOrNull => switch (this) {
    AsyncData<T>(:final value) => value,
    AsyncLoading<T>(:final previousData) => previousData,
    _ => null,
  };

  bool get isLoading => this is AsyncLoading<T>;
  bool get hasError => this is AsyncError<T>;
}

class AsyncData<T> extends AsyncValue<T> {
  final T value;

  const AsyncData(this.value);
}

class AsyncLoading<T> extends AsyncValue<T> {
  final T? previousData;

  const AsyncLoading([this.previousData]);
}

class AsyncError<T> extends AsyncValue<T> {
  final Object error;
  final StackTrace stackTrace;

  const AsyncError(this.error, this.stackTrace);
}

/// Adds mounted-safe async execution helpers directly on async state nodes.
extension SafeAsyncNodeX<T> on ZenithNode<AsyncValue<T>> {
  /// Executes [future] and writes its result to this node, guarding every
  /// mutation with [ref]'s lifecycle. Equivalent to `ref.runAsync(this, future)`.
  Future<void> guard(ZenithRef ref, Future<T> Function() future) {
    return ref.runAsync(this, future);
  }
}
