import 'zenith_key.dart';
import 'zenith_node.dart';

typedef NodeKey = Object;

class ZenithRef {
  final ZenithContainer container;
  bool _isMounted = true;
  final List<void Function()> _onDisposeCallbacks = <void Function()>[];

  ZenithRef(this.container);

  bool get isMounted => _isMounted;

  T read<T>(ZenithNode<T> node) => node.value;

  void onDispose(void Function() callback) {
    if (!_isMounted) {
      callback();
      return;
    }
    _onDisposeCallbacks.add(callback);
  }

  void _dispose() {
    if (!_isMounted) {
      return;
    }

    _isMounted = false;

    for (final callback in List<void Function()>.from(_onDisposeCallbacks)) {
      callback();
    }

    _onDisposeCallbacks.clear();
  }
}

class ZenithContainer {
  final ZenithContainer? parent;
  final Map<NodeKey, ZenithNode<dynamic>> _nodes =
      <NodeKey, ZenithNode<dynamic>>{};
  final Map<NodeKey, ZenithRef> _refs = <NodeKey, ZenithRef>{};
  final Map<ZenithKey<dynamic>, Function> _overrides;
  bool _isDisposed = false;

  ZenithContainer({
    this.parent,
    List<ZenithOverride<dynamic>> overrides = const [],
  }) : _overrides = {
         for (final override in overrides) override.key: override.factory,
       };

  bool get isDisposed => _isDisposed;

  ZenithNode<T> getOrCreateNode<T>(
    NodeKey key,
    T Function(ZenithRef ref) factory,
  ) {
    if (_isDisposed) {
      throw StateError('Cannot create node in disposed ZenithContainer');
    }

    final existing = _nodes[key];
    if (existing != null) {
      return existing as ZenithNode<T>;
    }

    final ref = ZenithRef(this);
    _refs[key] = ref;

    final initialValue = factory(ref);
    final node = ZenithNode<T>(initialValue);
    _nodes[key] = node;
    return node;
  }

  /// Type-safe node retrieval or creation using a [ZenithKey].
  ///
  /// If a [ZenithOverride] was registered for [key] on this container, its
  /// factory is used instead of [factory]. Nodes created this way live in
  /// the same internal storage as [getOrCreateNode], so [invalidate] and
  /// [invalidateKey] both operate on them consistently.
  ZenithNode<T> getOrCreate<T>(
    ZenithKey<T> key,
    T Function(ZenithRef ref) factory,
  ) {
    if (_isDisposed) {
      throw StateError('Cannot create node in disposed ZenithContainer');
    }

    final existing = _nodes[key];
    if (existing != null) {
      return existing as ZenithNode<T>;
    }

    final overrideFactory = _overrides[key] as T Function(ZenithRef ref)?;
    final effectiveFactory = overrideFactory ?? factory;

    final ref = ZenithRef(this);
    _refs[key] = ref;

    final initialValue = effectiveFactory(ref);
    final node = ZenithNode<T>(initialValue);
    _nodes[key] = node;
    return node;
  }

  ZenithNode<T>? maybeNode<T>(NodeKey key) {
    final local = _nodes[key];
    if (local != null) {
      return local as ZenithNode<T>;
    }

    return null;
  }

  /// Type-safe optional node lookup that also checks parent containers.
  ZenithNode<T>? maybeReadKey<T>(ZenithKey<T> key) {
    final local = _nodes[key];
    if (local != null) {
      return local as ZenithNode<T>;
    }

    return parent?.maybeReadKey<T>(key);
  }

  void invalidate(NodeKey key) {
    if (_isDisposed) {
      return;
    }

    final node = _nodes[key];
    if (node != null) {
      node.invalidate();
      return;
    }

    parent?.invalidate(key);
  }

  /// Type-safe convenience wrapper around [invalidate] for a [ZenithKey].
  void invalidateKey<T>(ZenithKey<T> key) {
    invalidate(key);
  }

  void dispose() {
    if (_isDisposed) {
      return;
    }

    _isDisposed = true;

    for (final ref in _refs.values.toList(growable: false)) {
      ref._dispose();
    }

    for (final node in _nodes.values.toList(growable: false)) {
      node.dispose();
    }

    _refs.clear();
    _nodes.clear();
  }
}
