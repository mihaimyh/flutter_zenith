import 'zenith_node.dart';

/// Interceptor interface for observing, sanitizing, transforming, or canceling
/// value mutations on a [ZenithNode].
///
/// Implement this interface to create middleware for logging, value clamping,
/// bearer token injection, analytics, or validation.
///
/// ```dart
/// class ClampingMiddleware extends ZenithMiddleware<int> {
///   @override
///   int? onWillSet(ZenithNode<int> node, int currentValue, int newValue) {
///     return newValue.clamp(0, 100);
///   }
/// }
/// ```
abstract class ZenithMiddleware<T> {
  /// Called before [newValue] is assigned to [node].
  ///
  /// - Return a modified value to transform the incoming value before assignment.
  /// - Return [newValue] unchanged to allow normal write.
  /// - Return `null` to cancel/block the write operation entirely.
  T? onWillSet(ZenithNode<T> node, T currentValue, T newValue) => newValue;

  /// Called after [value] has been successfully assigned to [node] and
  /// subscribers have been notified.
  void onDidSet(ZenithNode<T> node, T value) {}
}
