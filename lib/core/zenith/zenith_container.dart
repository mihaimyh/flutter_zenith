import 'async_value.dart';
import 'zenith_key.dart';
import 'zenith_node.dart';

/// The key type used for node lookup in a [ZenithContainer].
///
/// Can be a plain [String], a [ZenithKey<T>], or any [Object] with proper
/// `==` and `hashCode` semantics.
typedef NodeKey = Object;

/// A scoped lifecycle handle for a single node's factory context.
///
/// Each node created via [ZenithContainer.getOrCreateNode] or
/// [ZenithContainer.getOrCreate] receives its own [ZenithRef]. The ref
/// provides:
/// - [isMounted] — whether the owning container is still alive.
/// - [set] — mounted-safe value writes that silently no-op after disposal.
/// - [runAsync] — mounted-safe async execution with automatic
///   `AsyncLoading`/`AsyncData`/`AsyncError` transitions.
/// - [onDispose] — register teardown callbacks that run when the container
///   is disposed.
///
/// All methods that mutate state are guarded by [isMounted], so callers
/// never need to manually check lifecycle status after async boundaries.
class ZenithRef {
  /// The container that owns this ref.
  final ZenithContainer container;

  bool _isMounted = true;
  final List<void Function()> _onDisposeCallbacks = <void Function()>[];

  /// Creates a [ZenithRef] bound to [container].
  ZenithRef(this.container);

  /// Whether the owning container is still alive.
  ///
  /// Returns `false` after the container has been disposed.
  bool get isMounted => _isMounted;

  /// Reads the current value of [node].
  T read<T>(ZenithNode<T> node) => node.value;

  /// Safely sets [node] to [value] only if this ref is still mounted.
  ///
  /// Silently drops the update if the underlying scope/container has been
  /// disposed, so callers never need to manually check [isMounted] before
  /// mutating state.
  void set<T>(ZenithNode<T> node, T value) {
    if (!_isMounted) return;
    node.set(value);
  }

  /// Safely runs an async [task] and writes its result to [node], guarding
  /// every mutation with this ref's mounted state.
  ///
  /// Sets [node] to [AsyncLoading] (preserving any previous data) before
  /// awaiting [task], then to [AsyncData] on success or [AsyncError] on
  /// failure — but only if this ref is still mounted at each step. This
  /// eliminates the need for manual `if (!ref.isMounted) return;` checks
  /// after async boundaries.
  Future<void> runAsync<T>(
    ZenithNode<AsyncValue<T>> node,
    Future<T> Function() task,
  ) async {
    if (!_isMounted) return;
    node.set(AsyncLoading<T>(node.value.valueOrNull));

    try {
      final data = await task();
      if (!_isMounted) return;
      node.set(AsyncData<T>(data));
    } catch (error, stackTrace) {
      if (!_isMounted) return;
      node.set(AsyncError<T>(error, stackTrace));
    }
  }

  /// Registers a [callback] to run when the owning container is disposed.
  ///
  /// If the ref is already disposed when this is called, [callback] is
  /// invoked immediately.
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

/// A scoped dependency injection container that manages [ZenithNode]s and
/// their lifecycle.
///
/// Nodes are created on-demand via [getOrCreateNode] (string keys) or
/// [getOrCreate] (typed [ZenithKey]s). Each node receives its own [ZenithRef]
/// with lifecycle hooks. When the container is [dispose]d, all refs fire
/// their `onDispose` callbacks and all nodes are disposed — preventing memory
/// leaks and stale state.
///
/// Containers support a [parent] hierarchy for dependency fallback. A child
/// container creates its own independent nodes but can look up missing keys
/// in its parent via [maybeReadKey] and [invalidate].
///
/// For testing or feature scoping, pass [overrides] to replace factory
/// functions for specific [ZenithKey]s.
///
/// ```dart
/// final container = ZenithContainer();
/// final node = container.getOrCreateNode<int>('counter', (_) => 0);
/// node.set(1);
/// container.dispose(); // tears down everything
/// ```
class ZenithContainer {
  /// Optional parent container for hierarchical dependency resolution.
  final ZenithContainer? parent;

  final Map<NodeKey, ZenithNode<dynamic>> _nodes =
      <NodeKey, ZenithNode<dynamic>>{};
  final Map<NodeKey, ZenithRef> _refs = <NodeKey, ZenithRef>{};
  final Map<ZenithKey<dynamic>, Function> _overrides;
  bool _isDisposed = false;

  /// Creates a [ZenithContainer], optionally with a [parent] for fallback
  /// resolution and [overrides] for factory substitution.
  ZenithContainer({
    this.parent,
    List<ZenithOverride<dynamic>> overrides = const [],
  }) : _overrides = {
         for (final override in overrides) override.key: override.factory,
       };

  /// Whether this container has been disposed.
  bool get isDisposed => _isDisposed;

  /// Retrieves or creates a node identified by [key].
  ///
  /// If a node for [key] already exists, returns the cached instance
  /// (cast to `ZenithNode<T>`). Otherwise, invokes [factory] with a fresh
  /// [ZenithRef] to produce the initial value, wraps it in a [ZenithNode],
  /// caches it, and returns it.
  ///
  /// Throws [StateError] if the container has been disposed.
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
  ///
  /// Throws [StateError] if the container has been disposed.
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

  /// Returns the node for [key] if it exists in this container, or `null`.
  ///
  /// Does **not** fall back to [parent] — use [maybeReadKey] for
  /// hierarchical lookup.
  ZenithNode<T>? maybeNode<T>(NodeKey key) {
    final local = _nodes[key];
    if (local != null) {
      return local as ZenithNode<T>;
    }

    return null;
  }

  /// Type-safe optional node lookup that also checks parent containers.
  ///
  /// Returns the node for [key] from this container or the nearest ancestor
  /// that has it, or `null` if no container in the chain has the key.
  ZenithNode<T>? maybeReadKey<T>(ZenithKey<T> key) {
    final local = _nodes[key];
    if (local != null) {
      return local as ZenithNode<T>;
    }

    return parent?.maybeReadKey<T>(key);
  }

  /// Invalidates (re-notifies subscribers of) the node identified by [key].
  ///
  /// If the key does not exist in this container, the invalidation request
  /// bubbles up to the [parent] container (if any).
  ///
  /// Safe to call on a disposed container (no-op).
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

  /// Disposes this container, firing all `onDispose` callbacks and
  /// disposing all managed nodes.
  ///
  /// After disposal:
  /// - [isDisposed] returns `true`.
  /// - [getOrCreateNode] and [getOrCreate] throw [StateError].
  /// - [maybeNode] and [maybeReadKey] return `null`.
  ///
  /// Calling [dispose] on an already-disposed container is a safe no-op
  /// (idempotent).
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
