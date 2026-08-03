import 'package:flutter/widgets.dart';

import 'zenith_container.dart';
import 'zenith_node.dart';

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

class ZenithBuilder extends StatefulWidget {
  final Widget Function(BuildContext context) builder;

  const ZenithBuilder({super.key, required this.builder});

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
      return widget.builder(context);
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
