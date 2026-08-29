import 'async_value.dart';
import 'zenith_container.dart';
import 'zenith_node.dart';

/// Represents the state and execution of a discrete asynchronous action.
///
/// Use mutations for user-initiated work such as saving a form, purchasing,
/// deleting, or exporting. They retain the last successful value while a
/// subsequent operation is pending and ignore stale results by default.
class ZenithMutation<T> {
  /// Creates a mutation that writes operation state to [state].
  ZenithMutation({
    required this._ref,
    required this.state,
  });

  final ZenithRef _ref;

  /// Reactive state for the latest execution.
  final ZenithNode<AsyncValue<T>> state;

  int _generation = 0;

  /// Whether an execution is currently pending.
  bool get isPending => state.value.isLoading;

  /// Runs [operation] and returns its result when this execution remains
  /// current. A stale or disposed execution returns `null`; a current failed
  /// operation records [AsyncError] and rethrows its error to the caller.
  Future<T?> run(Future<T> Function() operation) async {
    final generation = ++_generation;
    _ref.set(state, AsyncLoading<T>(state.value.valueOrNull));

    try {
      final value = await operation();
      if (!_ref.isMounted || generation != _generation) return null;
      _ref.set(state, AsyncData<T>(value));
      return value;
    } catch (error, stackTrace) {
      if (!_ref.isMounted || generation != _generation) return null;
      _ref.set(state, AsyncError<T>(error, stackTrace));
      rethrow;
    }
  }
}