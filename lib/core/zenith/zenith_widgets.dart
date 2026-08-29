import 'package:flutter/widgets.dart';

import 'zenith_container.dart';
import 'zenith_key.dart';
import 'zenith_node.dart';

/// An [InheritedWidget] wrapper that binds a [ZenithContainer] to a subtree
/// of the widget tree.
///
/// When the [container] is swapped (e.g., on user logout / session change),
/// the old container is automatically disposed in [didUpdateWidget].
/// When the scope is removed from the tree, the container is disposed in
/// [dispose].
///
/// To force a clean container swap on session change, assign a distinct
/// [ValueKey] to the [ZenithScope]:
///
/// ```dart
/// ZenithScope(
///   key: ValueKey(userId),
///   container: container,
///   child: const MyApp(),
/// )
/// ```
class ZenithScope extends StatefulWidget {
  /// The container to provide to descendant widgets.
  final ZenithContainer container;

  /// The widget subtree that can access [container] via [ZenithScope.of].
  final Widget child;

  /// Creates a [ZenithScope] that binds [container] to the [child] subtree.
  const ZenithScope({super.key, required this.container, required this.child});

  /// Retrieves the nearest [ZenithContainer] from the widget tree.
  ///
  /// Throws an [AssertionError] in debug mode if:
  /// - No [ZenithScope] exists above [context].
  /// - The resolved container has already been disposed.
  static ZenithContainer of(BuildContext context) {
    final inherited = context
        .dependOnInheritedWidgetOfExactType<_ZenithScopeInherited>();

    assert(inherited != null, 'No ZenithScope found in BuildContext hierarchy');

    final container = inherited!.container;
    assert(
      !container.isDisposed,
      'Attempted to access a disposed ZenithContainer from BuildContext',
    );

    return container;
  }

  @override
  State<ZenithScope> createState() => _ZenithScopeState();
}

class _ZenithScopeState extends State<ZenithScope> {
  @override
  void didUpdateWidget(covariant ZenithScope oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!identical(oldWidget.container, widget.container)) {
      oldWidget.container.dispose();
    }
  }

  @override
  void dispose() {
    widget.container.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _ZenithScopeInherited(
      container: widget.container,
      child: widget.child,
    );
  }
}

class _ZenithScopeInherited extends InheritedWidget {
  final ZenithContainer container;

  const _ZenithScopeInherited({required this.container, required super.child});

  @override
  bool updateShouldNotify(covariant _ZenithScopeInherited oldWidget) {
    return !identical(oldWidget.container, container);
  }
}

/// A widget that subscribes to [ZenithNode]s read inside its [builder]
/// closure and surgically rebuilds only when those nodes change.
///
/// Dependencies are auto-tracked: any [ZenithNode.value] read during
/// [builder] execution is subscribed to. On subsequent builds, stale
/// subscriptions (nodes no longer read) are reconciled away.
///
/// ```dart
/// ZenithBuilder(
///   builder: (context) {
///     final count = counterNode.value; // auto-subscribed
///     return Text('Count: $count');
///   },
/// )
/// ```
///
/// If the builder throws, [errorBuilder] is invoked (if provided) to render
/// a fallback widget. If [errorBuilder] is not set, the error propagates
/// normally.
class ZenithBuilder extends StatefulWidget {
  /// The builder function that reads [ZenithNode]s and returns a widget.
  ///
  /// Any [ZenithNode.value] accessed inside this closure is automatically
  /// subscribed to — changes to those nodes trigger a rebuild of only this
  /// widget.
  final Widget Function(BuildContext context) builder;

  /// Optional error handler invoked when [builder] throws an exception.
  ///
  /// If `null`, exceptions propagate normally. When provided, the widget
  /// renders the result of [errorBuilder] instead of crashing.
  final Widget Function(BuildContext context, Object error, StackTrace stack)?
      errorBuilder;

  /// Creates a [ZenithBuilder].
  const ZenithBuilder({super.key, required this.builder, this.errorBuilder});

  @override
  State<ZenithBuilder> createState() => _ZenithBuilderState();
}

class _ZenithBuilderState extends State<ZenithBuilder>
    implements ZenithSubscriber, ZenithObserverTracker {
  final Set<ZenithNode<dynamic>> _observedNodes = <ZenithNode<dynamic>>{};
  final Set<ZenithNode<dynamic>> _nodesReadThisBuild = <ZenithNode<dynamic>>{};
  bool _isCollectingDependencies = false;

  @override
  void onNodeChanged(ZenithNode<dynamic> node) {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void onNodeRead(ZenithNode<dynamic> node) {
    if (_isCollectingDependencies) {
      _nodesReadThisBuild.add(node);
    }
  }

  void _reconcileSubscriptions() {
    final staleNodes = _observedNodes
        .where((node) => !_nodesReadThisBuild.contains(node))
        .toList(growable: false);

    for (final node in staleNodes) {
      node.unsubscribe(this);
    }

    _observedNodes
      ..clear()
      ..addAll(_nodesReadThisBuild);
  }

  @override
  Widget build(BuildContext context) {
    final previousObserver = ZenithZone.currentObserver;
    _nodesReadThisBuild.clear();
    _isCollectingDependencies = true;
    ZenithZone.currentObserver = this;

    try {
      final result = widget.builder(context);
      return result;
    } catch (error, stack) {
      if (widget.errorBuilder != null) {
        return widget.errorBuilder!(context, error, stack);
      }
      rethrow;
    } finally {
      _isCollectingDependencies = false;
      ZenithZone.currentObserver = previousObserver;
      _reconcileSubscriptions();
    }
  }

  @override
  void dispose() {
    for (final node in _observedNodes.toList(growable: false)) {
      node.unsubscribe(this);
    }
    _observedNodes.clear();
    _nodesReadThisBuild.clear();
    super.dispose();
  }
}

/// Ergonomic helpers so widgets can access the current [ZenithContainer]
/// directly from a [BuildContext] without a verbose [ZenithScope.of] call.
extension ZenithContextX on BuildContext {
  /// Resolves the current [ZenithContainer] from the nearest [ZenithScope].
  ZenithContainer get container => ZenithScope.of(this);

  /// Type-safe helper to read or create a node using a [ZenithKey].
  ///
  /// Looks up [key] in the nearest [ZenithContainer] and creates the node
  /// via [factory] if it doesn't already exist.
  ZenithNode<T> zenith<T>(
    ZenithKey<T> key,
    T Function(ZenithRef ref) factory,
  ) {
    return ZenithScope.of(this).getOrCreate<T>(key, factory);
  }
}
