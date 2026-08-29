import 'dart:async';

import 'async_value.dart';
import 'zenith_container.dart';
import 'zenith_node.dart';

/// Adds stream subscription helpers to [ZenithRef].
///
/// Use [watchStream] to bind a [Stream] to an [AsyncValue] node. The stream
/// subscription is automatically cancelled when the ref's scope is disposed.
extension ZenithStreamX on ZenithRef {
  /// Subscribes to [stream] and writes each event to [node] as [AsyncData].
  ///
  /// Sets [node] to [AsyncLoading] immediately (preserving any previous data),
  /// then maps each stream event to [AsyncData] and each error to
  /// [AsyncError]. The subscription is automatically cancelled via
  /// [ZenithRef.onDispose], so no manual cleanup is needed.
  ///
  /// Returns the underlying [StreamSubscription] in case you need to pause,
  /// resume, or cancel it earlier than disposal.
  ///
  /// ```dart
  /// class ChatController {
  ///   final messagesNode = ZenithNode<AsyncValue<List<Message>>>(
  ///     const AsyncLoading(),
  ///   );
  ///
  ///   void listen(ZenithRef ref, Stream<List<Message>> stream) {
  ///     ref.watchStream(messagesNode, stream);
  ///   }
  /// }
  /// ```
  StreamSubscription<T> watchStream<T>(
    ZenithNode<AsyncValue<T>> node,
    Stream<T> stream,
  ) {
    if (!isMounted) {
      // Ref already disposed — subscribe and immediately cancel to return
      // a valid, inert StreamSubscription without blocking.
      final subscription = stream.listen(null);
      subscription.cancel();
      return subscription;
    }

    set<AsyncValue<T>>(node, AsyncLoading<T>(node.value.valueOrNull));

    final subscription = stream.listen(
      (data) {
        if (!isMounted) return;
        set<AsyncValue<T>>(node, AsyncData<T>(data));
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!isMounted) return;
        set<AsyncValue<T>>(node, AsyncError<T>(error, stackTrace));
      },
    );

    onDispose(subscription.cancel);

    return subscription;
  }
}

/// Adds stream subscription helpers directly on [AsyncValue] nodes.
extension StreamNodeX<T> on ZenithNode<AsyncValue<T>> {
  /// Subscribes to [stream] and writes each event to this node, guarding
  /// every mutation with [ref]'s lifecycle.
  ///
  /// Equivalent to `ref.watchStream(this, stream)`.
  StreamSubscription<T> watch(ZenithRef ref, Stream<T> stream) {
    return ref.watchStream(this, stream);
  }
}
