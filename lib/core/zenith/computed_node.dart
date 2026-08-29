import 'zenith_node.dart';

/// A read-only reactive node whose value is automatically derived from other
/// [ZenithNode]s.
///
/// During the initial [compute] call and every subsequent re-computation, a
/// [ZenithZone] observer is installed to auto-track which source nodes are
/// read. When any tracked source changes, [compute] runs again and, if the
/// result differs from the previous value, downstream subscribers are
/// notified.
///
/// ```dart
/// final firstName = ZenithNode<String>('John');
/// final lastName  = ZenithNode<String>('Doe');
/// final fullName  = ComputedNode<String>(
///   () => '${firstName.value} ${lastName.value}',
/// );
///
/// // fullName.value == 'John Doe'
/// firstName.set('Jane');
/// // fullName.value == 'Jane Doe' — downstream ZenithBuilders rebuild.
/// ```
///
/// **Important:** Do not call [set] on a [ComputedNode]. The value is managed
/// exclusively by the [compute] function. Calling [set] will throw a
/// [StateError].
class ComputedNode<T> extends ZenithNode<T>
    implements ZenithSubscriber, ZenithObserverTracker {
  final T Function() _compute;

  /// The set of source nodes that were read during the last computation.
  final Set<ZenithNode<dynamic>> _trackedSources = <ZenithNode<dynamic>>{};
  final Set<ZenithNode<dynamic>> _nodesReadThisCompute =
      <ZenithNode<dynamic>>{};
  bool _isCollectingDependencies = false;

  /// Creates a [ComputedNode] that derives its value from [compute].
  ///
  /// [compute] is invoked immediately to establish the initial value and
  /// discover source dependencies.
  ComputedNode(this._compute) : super(_compute()) {
    _recompute();
  }

  @override
  void onNodeRead(ZenithNode<dynamic> node) {
    if (_isCollectingDependencies) {
      _nodesReadThisCompute.add(node);
    }
  }

  void _recompute() {
    final previousObserver = ZenithZone.currentObserver;
    _nodesReadThisCompute.clear();
    _isCollectingDependencies = true;
    ZenithZone.currentObserver = this;

    T newValue;
    try {
      newValue = _compute();
    } finally {
      _isCollectingDependencies = false;
      ZenithZone.currentObserver = previousObserver;
    }

    // Reconcile subscriptions: unsubscribe from nodes no longer read.
    final stale = _trackedSources.difference(_nodesReadThisCompute);
    for (final node in stale) {
      node.unsubscribe(this);
    }

    _trackedSources
      ..clear()
      ..addAll(_nodesReadThisCompute);

    // Update internal value and notify downstream subscribers if changed.
    super.set(newValue);
  }

  /// Called when any tracked source node changes.
  @override
  void onNodeChanged(ZenithNode<dynamic> node) {
    if (isDisposed) return;
    _recompute();
  }

  /// Computed nodes are read-only. Calling [set] throws a [StateError].
  @override
  void set(T newValue) {
    throw StateError(
      'Cannot set a ComputedNode directly. '
      'Its value is derived from the compute function.',
    );
  }

  @override
  void dispose() {
    for (final node in _trackedSources.toList(growable: false)) {
      node.unsubscribe(this);
    }
    _trackedSources.clear();
    _nodesReadThisCompute.clear();
    super.dispose();
  }
}
