import 'package:flutter/foundation.dart' show debugPrint;

abstract class ZenithSubscriber {
  void onNodeChanged(ZenithNode<dynamic> node);
}

abstract class ZenithObserverTracker {
  void onNodeRead(ZenithNode<dynamic> node);
}

class ZenithZone {
  static ZenithSubscriber? currentObserver;
}

class ZenithNode<T> {
  T _value;
  bool _isDisposed = false;
  bool _isInvalidating = false;
  final Set<WeakReference<ZenithSubscriber>> _subscribers =
      <WeakReference<ZenithSubscriber>>{};

  ZenithNode(this._value);

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

  bool get isDisposed => _isDisposed;

  int get debugSubscriberCount => _subscribers.length;

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

  void unsubscribe(ZenithSubscriber subscriber) {
    if (_isDisposed) {
      return;
    }

    _subscribers.removeWhere((weak) {
      final target = weak.target;
      return target == null || identical(target, subscriber);
    });
  }

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

  void dispose() {
    if (_isDisposed) {
      return;
    }

    _isDisposed = true;
    _subscribers.clear();
  }
}
