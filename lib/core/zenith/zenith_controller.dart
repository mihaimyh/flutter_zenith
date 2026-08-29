import 'dart:async';

import 'async_value.dart';
import 'zenith_container.dart';
import 'zenith_node.dart';
import 'zenith_stream.dart';

/// Base class for business logic controllers bound to a [ZenithRef] scope.
///
/// Encapsulates state mutations, async task execution, stream watching,
/// and automatic lifecycle cleanup.
abstract class ZenithController {
  /// The scoped [ZenithRef] managing this controller's lifecycle.
  final ZenithRef ref;

  /// Creates a [ZenithController] and registers [onDispose] with [ref].
  ZenithController(this.ref) {
    ref.onDispose(onDispose);
    onInit();
  }

  /// Called immediately upon controller creation.
  void onInit() {}

  /// Called when the owning [ZenithContainer] or [ZenithRef] scope is disposed or reset.
  void onDispose() {}

  /// Whether the owning container/scope is still mounted.
  bool get isMounted => ref.isMounted;

  /// Safely mutates [node] if the controller is still mounted.
  void set<T>(ZenithNode<T> node, T value) {
    ref.set(node, value);
  }

  /// Safely runs [task] and updates [node] with `AsyncLoading`/`AsyncData`/`AsyncError`.
  Future<void> runAsync<T>(
    ZenithNode<AsyncValue<T>> node,
    Future<T> Function() task,
  ) {
    return ref.runAsync(node, task);
  }

  /// Subscribes to [stream] and writes events to [node], cancelling on disposal.
  StreamSubscription<T> watchStream<T>(
    ZenithNode<AsyncValue<T>> node,
    Stream<T> stream,
  ) {
    return ref.watchStream(node, stream);
  }
}
