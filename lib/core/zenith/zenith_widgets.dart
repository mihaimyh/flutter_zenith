import 'package:flutter/widgets.dart';

import 'zenith_container.dart';
import 'zenith_key.dart';
import 'zenith_node.dart';

/// An [InheritedWidget] wrapper that binds a [ZenithContainer] to a subtree
/// of the widget tree.
class ZenithScope extends StatefulWidget {
  final ZenithContainer container;
  final Widget child;

  const ZenithScope({super.key, required this.container, required this.child});

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
class ZenithBuilder extends StatefulWidget {
  final Widget Function(BuildContext context) builder;
  final Widget Function(BuildContext context, Object error, StackTrace stack)?
      errorBuilder;

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

/// A drop-in replacement for Riverpod's ConsumerWidget.
///
/// Automatically tracks any Zenith node accessed during [buildConsumer].
abstract class ZenithConsumerWidget extends StatelessWidget {
  const ZenithConsumerWidget({super.key});

  /// Build method that receives the [ZenithContainer] for convenience.
  Widget buildConsumer(BuildContext context, ZenithContainer container);

  @override
  Widget build(BuildContext context) {
    return ZenithBuilder(
      builder: (ctx) => buildConsumer(ctx, ctx.container),
    );
  }
}

/// A widget that fires [listener] callbacks for side-effects (navigation, dialogs, snackbars)
/// whenever [node] changes, without triggering UI rebuilds.
class ZenithListener<T> extends StatefulWidget {
  final ZenithNode<T> node;
  final void Function(BuildContext context, T previous, T current) listener;
  final Widget child;

  const ZenithListener({
    super.key,
    required this.node,
    required this.listener,
    required this.child,
  });

  @override
  State<ZenithListener<T>> createState() => _ZenithListenerState<T>();
}

class _ZenithListenerState<T> extends State<ZenithListener<T>>
    implements ZenithSubscriber {
  late T _previousValue;

  @override
  void initState() {
    super.initState();
    _previousValue = widget.node.value;
    widget.node.subscribe(this);
  }

  @override
  void didUpdateWidget(covariant ZenithListener<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.node, widget.node)) {
      oldWidget.node.unsubscribe(this);
      _previousValue = widget.node.value;
      widget.node.subscribe(this);
    }
  }

  @override
  void onNodeChanged(ZenithNode<dynamic> node) {
    if (mounted) {
      final currentValue = widget.node.value;
      widget.listener(context, _previousValue, currentValue);
      _previousValue = currentValue;
    }
  }

  @override
  void dispose() {
    widget.node.unsubscribe(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Ergonomic helpers so widgets can access the current [ZenithContainer]
/// directly from a [BuildContext] without a verbose [ZenithScope.of] call.
extension ZenithContextX on BuildContext {
  /// Resolves the current [ZenithContainer] from the nearest [ZenithScope].
  ZenithContainer get container => ZenithScope.of(this);

  /// Type-safe helper to read or create a node using a [ZenithKey].
  ZenithNode<T> zenith<T>(
    ZenithKey<T> key,
    T Function(ZenithRef ref) factory,
  ) {
    return ZenithScope.of(this).getOrCreate<T>(key, factory);
  }

  /// Evaluates and registers auto-subscription for [node] if called inside
  /// a [ZenithBuilder] or [ZenithConsumerWidget].
  T watchNode<T>(ZenithNode<T> node) {
    return node.value;
  }

  /// Selects a field from [node], registering zone auto-subscription.
  R selectNode<T, R>(ZenithNode<T> node, R Function(T state) selector) {
    return selector(node.value);
  }
}
