import 'package:flutter/foundation.dart' show debugPrint;

import 'zenith_container.dart';
import 'zenith_node.dart';

/// An observer that receives lifecycle events from the Zenith framework.
///
/// Register a global observer via [Zenith.observer] to monitor node creation,
/// mutations, disposal, and container lifecycle events. Useful for debugging,
/// analytics, or logging.
///
/// ```dart
/// Zenith.observer = ZenithLogObserver(); // logs all events in debug mode
/// ```
abstract class ZenithObserver {
  /// Called when a new [ZenithNode] is created in [container] with [key].
  void onNodeCreated(ZenithContainer container, Object key, ZenithNode<dynamic> node) {}

  /// Called when a [ZenithNode]'s value is updated.
  void onNodeMutated(ZenithNode<dynamic> node, dynamic oldValue, dynamic newValue) {}

  /// Called when a [ZenithNode] is disposed.
  void onNodeDisposed(ZenithNode<dynamic> node) {}

  /// Called when a [ZenithContainer] is created.
  void onContainerCreated(ZenithContainer container) {}

  /// Called when a [ZenithContainer] is disposed.
  void onContainerDisposed(ZenithContainer container) {}
}

/// Global configuration for the Zenith framework.
///
/// Currently provides a single hook: [observer], which receives lifecycle
/// events from all containers and nodes. Set to `null` to disable
/// observation (the default).
class Zenith {
  Zenith._();

  /// The global observer that receives lifecycle events.
  ///
  /// Set this early in your app (e.g. in `main()`) to enable debugging:
  /// ```dart
  /// void main() {
  ///   Zenith.observer = ZenithLogObserver();
  ///   runApp(const MyApp());
  /// }
  /// ```
  static ZenithObserver? observer;
}

/// A built-in [ZenithObserver] that logs all events via [debugPrint].
///
/// Only prints in debug mode (assertions enabled). In release mode, all
/// calls are no-ops.
class ZenithLogObserver extends ZenithObserver {
  @override
  void onNodeCreated(ZenithContainer container, Object key, ZenithNode<dynamic> node) {
    assert(() {
      debugPrint('[Zenith] Node created: key=$key');
      return true;
    }());
  }

  @override
  void onNodeMutated(ZenithNode<dynamic> node, dynamic oldValue, dynamic newValue) {
    assert(() {
      debugPrint('[Zenith] Node mutated: $oldValue → $newValue');
      return true;
    }());
  }

  @override
  void onNodeDisposed(ZenithNode<dynamic> node) {
    assert(() {
      debugPrint('[Zenith] Node disposed');
      return true;
    }());
  }

  @override
  void onContainerCreated(ZenithContainer container) {
    assert(() {
      debugPrint('[Zenith] Container created');
      return true;
    }());
  }

  @override
  void onContainerDisposed(ZenithContainer container) {
    assert(() {
      debugPrint('[Zenith] Container disposed');
      return true;
    }());
  }
}
