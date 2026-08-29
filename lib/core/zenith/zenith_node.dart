import 'package:flutter/foundation.dart' show debugPrint;

/// Interface for objects that want to be notified when a [ZenithNode] changes.
///
/// Subscribers are held via [WeakReference] inside the node, so they will be
/// automatically collected by the GC if no other strong reference exists.
abstract class ZenithSubscriber {
  /// Called when [node]'s value changes or it is invalidated.
  void onNodeChanged(ZenithNode<dynamic> node);
}

/// Optional interface for subscribers that also want to track which nodes
/// are being read (used internally by [ZenithBuilder] and [ComputedNode]
/// for automatic dependency collection).
abstract class ZenithObserverTracker {
  /// Called when a [ZenithNode.value] getter is invoked while this tracker
  /// is the active [ZenithZone.currentObserver].
  void onNodeRead(ZenithNode<dynamic> node);
}

/// Global zone state for automatic dependency tracking.
///
/// When a [ZenithBuilder] or [ComputedNode] is collecting dependencies,
/// it sets [currentObserver] before executing its builder/compute function
/// and restores it afterward.
class ZenithZone {
  /// The currently active observer, or `null` if no dependency collection
  /// is in progress.
  static ZenithSubscriber? currentObserver;
}

/// An atomic, observable state cell holding a value of type [T].
///
/// Subscribers registered via [subscribe] (or automatically via
/// [ZenithBuilder]) are notified through [WeakReference]-based tracking
/// whenever the value changes. Dead subscribers are automatically pruned
/// during notification passes, preventing memory leaks even if a subscriber
/// forgets to call [unsubscribe].
///
/// ```dart
/// final counter = ZenithNode<int>(0);
/// counter.set(1);         // notifies all subscribers
/// print(counter.value);   // 1
/// counter.dispose();      // releases all subscribers
/// ```
class ZenithNode<T> {
  T _value;
  bool _isDisposed = false;
  bool _isInvalidating = false;
  final Set<WeakReference<ZenithSubscriber>> _subscribers =
      <WeakReference<ZenithSubscriber>>{};

  /// Creates a [ZenithNode] with the given initial [value].
  ZenithNode(this._value);

  /// The current value held by this node.
  ///
  /// Reading this getter while a [ZenithZone.currentObserver] is active
  /// automatically subscribes that observer to this node (dependency
  /// tracking for [ZenithBuilder] and [ComputedNode]).
  ///
  /// Throws [StateError] if the node has been disposed.
  T get value {
    if (_isDisposed) {
      throw StateError('Cannot read a disposed ZenithNode');
    }

    final observer = ZenithZone.currentObserver;
    if (observer != null) {
      subscribe(observer);
      if (observer case ZenithObserverTracker tracker) {
        tracker.onNodeRead(this);
      }
    }

    return _value;
  }

  /// Whether this node has been disposed.
  ///
  /// A disposed node cannot be read, subscribed to, or invalidated.
  /// Calling [set] on a disposed node is a safe no-op.
  bool get isDisposed => _isDisposed;

  /// The current number of subscribers (including potentially dead weak
  /// references that have not yet been pruned).
  ///
  /// Intended for debugging and testing only.
  int get debugSubscriberCount => _subscribers.length;

  /// Updates the node's value to [newValue] and notifies subscribers.
  ///
  /// If [newValue] is equal to the current value (via `==`), this is a
  /// no-op and no notifications are sent.
  ///
  /// If the node has been disposed, the call is silently ignored (a debug
  /// message is printed in debug mode). This soft-fail behavior prevents
  /// crashes from late async writes that land after scope disposal.
  void set(T newValue) {
    if (_isDisposed) {
      // Late async writes after disposal are common and usually harmless (the
      // UI/scope is simply gone). Fail softly instead of throwing so callers
      // don't need to manually guard every post-await mutation.
      assert(() {
        debugPrint(
          'ZenithNode.set() ignored: node is disposed (value: $newValue)',
        );
        return true;
      }());
      return;
    }

    if (_value == newValue) {
      return;
    }

    _value = newValue;
    notifySubscribers();
  }

  /// Adds [subscriber] to this node's listener set.
  ///
  /// The subscriber is held via a [WeakReference] and is deduplicated by
  /// identity — subscribing the same instance multiple times is a no-op.
  ///
  /// Throws [StateError] if the node has been disposed.
  void subscribe(ZenithSubscriber subscriber) {
    if (_isDisposed) {
      throw StateError('Cannot subscribe to a disposed ZenithNode');
    }

    for (final weak in _subscribers) {
      if (identical(weak.target, subscriber)) {
        return;
      }
    }

    _subscribers.add(WeakReference<ZenithSubscriber>(subscriber));
  }

  /// Removes [subscriber] from this node's listener set.
  ///
  /// Also prunes any dead weak references encountered during removal.
  /// Safe to call on a disposed node (no-op).
  void unsubscribe(ZenithSubscriber subscriber) {
    if (_isDisposed) {
      return;
    }

    _subscribers.removeWhere((weak) {
      final target = weak.target;
      return target == null || identical(target, subscriber);
    });
  }

  /// Notifies all live subscribers that this node has changed.
  ///
  /// Dead weak references are pruned before and after the notification pass.
  /// The listener list is snapshot-copied before iteration so that mutations
  /// to the subscriber set during callbacks are safe.
  void notifySubscribers() {
    if (_isDisposed) {
      return;
    }

    _subscribers.removeWhere((weak) => weak.target == null);

    final listeners = List<ZenithSubscriber>.from(
      _subscribers.map((weak) => weak.target).whereType<ZenithSubscriber>(),
      growable: false,
    );

    for (final listener in listeners) {
      listener.onNodeChanged(this);
    }

    // Cleanup pass for listeners that were collected during notification.
    _subscribers.removeWhere((weak) => weak.target == null);
  }

  /// Forces a notification pass without changing the value.
  ///
  /// Useful for signaling subscribers to re-read the current value (e.g.,
  /// when a mutable object's internal state has changed without a new
  /// reference being assigned).
  ///
  /// Contains a re-entrancy guard: if [invalidate] is called recursively
  /// from within a notification callback, the nested call is a no-op. This
  /// also protects against circular invalidation between two nodes.
  ///
  /// Throws [StateError] if the node has been disposed.
  void invalidate() {
    if (_isDisposed) {
      throw StateError('Cannot invalidate a disposed ZenithNode');
    }

    if (_isInvalidating) {
      return;
    }

    _isInvalidating = true;
    try {
      notifySubscribers();
    } finally {
      _isInvalidating = false;
    }
  }

  /// Permanently disposes this node, clearing all subscribers.
  ///
  /// After disposal:
  /// - [value] and [invalidate] throw [StateError].
  /// - [set] is a safe no-op.
  /// - [subscribe] throws [StateError].
  ///
  /// Calling [dispose] on an already-disposed node is a safe no-op
  /// (idempotent).
  void dispose() {
    if (_isDisposed) {
      return;
    }

    _isDisposed = true;
    _subscribers.clear();
  }
}
