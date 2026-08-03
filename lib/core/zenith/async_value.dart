import 'package:flutter/foundation.dart';

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
