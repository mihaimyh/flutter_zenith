import 'dart:async';

import 'zenith_node.dart';
import 'zenith_storage.dart';

/// A specialized [ZenithNode] that automatically restores state from a
/// [ZenithStorage] backend on creation and saves updates on mutation.
///
/// ```dart
/// final themeNode = PersistedNode.string(
///   key: 'app.theme',
///   defaultValue: 'system',
///   storage: localStorage,
/// );
///
/// print(themeNode.value); // Restored from storage, or 'system'
/// themeNode.set('dark');  // Mutates node & asynchronously writes to storage
/// ```
class PersistedNode<T> extends ZenithNode<T> {
  static final _writes = Expando<Map<String, Future<void>>>();
  Future<void> _lastWrite = Future.value();
  Object? _persistenceError;
  int _generation = 0;

  /// Latest write/serialization failure, cleared after a successful write.
  Object? get persistenceError => _persistenceError;

  /// Awaits this node's latest accepted write and propagates its failure.
  /// Call before ending a scope when durability is required.
  Future<void> flush() => _lastWrite;

  /// The key used for storage lookup.
  final String key;

  /// The storage backend powering this node.
  final ZenithStorage storage;

  /// Serializer callback converting [T] to a [String].
  final String Function(T value) toStorage;

  /// Deserializer callback parsing [String] back into [T].
  final T Function(String raw) fromStorage;

  /// Creates a [PersistedNode] with custom serialization callbacks.
  PersistedNode({
    required this.key,
    required T defaultValue,
    required this.storage,
    required this.toStorage,
    required this.fromStorage,
  }) : super(_resolveInitial(key, defaultValue, storage, fromStorage));

  static T _resolveInitial<T>(
    String key,
    T defaultValue,
    ZenithStorage storage,
    T Function(String raw) fromStorage,
  ) {
    final raw = storage.read(key);
    if (raw == null) {
      return defaultValue;
    }
    try {
      return fromStorage(raw);
    } catch (_) {
      return defaultValue;
    }
  }

  /// Helper for string persisted nodes.
  static PersistedNode<String> string({
    required String key,
    required String defaultValue,
    required ZenithStorage storage,
  }) {
    return PersistedNode<String>(
      key: key,
      defaultValue: defaultValue,
      storage: storage,
      toStorage: (v) => v,
      fromStorage: (raw) => raw,
    );
  }

  /// Helper for integer persisted nodes.
  static PersistedNode<int> integer({
    required String key,
    required int defaultValue,
    required ZenithStorage storage,
  }) {
    return PersistedNode<int>(
      key: key,
      defaultValue: defaultValue,
      storage: storage,
      toStorage: (v) => v.toString(),
      fromStorage: (raw) => int.tryParse(raw) ?? defaultValue,
    );
  }

  /// Helper for boolean persisted nodes.
  static PersistedNode<bool> boolean({
    required String key,
    required bool defaultValue,
    required ZenithStorage storage,
  }) {
    return PersistedNode<bool>(
      key: key,
      defaultValue: defaultValue,
      storage: storage,
      toStorage: (v) => v.toString(),
      fromStorage: (raw) => raw.toLowerCase() == 'true',
    );
  }

  @override
  void set(T newValue) {
    if (isDisposed) return;
    final oldValue = value;
    if (oldValue == newValue) return;
    final generation = ++_generation;
    super.set(newValue);
    // A subscriber may dispose this node or synchronously write a newer value.
    if (isDisposed || generation != _generation || value == oldValue) return;
    try {
      final serialized = toStorage(value);
      final pending = _writes[storage] ??= {};
      final previous = pending[key] ?? Future<void>.value();
      final write = previous
          .then<void>((_) {}, onError: (Object _, StackTrace _) {})
          .then((_) => storage.write(key, serialized));
      pending[key] = write;
      _lastWrite = write;
      write.then(
        (_) {
          if (generation == _generation) _persistenceError = null;
          if (identical(pending[key], write)) pending.remove(key);
        },
        onError: (Object error, StackTrace stack) {
          if (generation == _generation) _persistenceError = error;
          if (identical(pending[key], write)) pending.remove(key);
        },
      );
    } catch (error, stack) {
      _persistenceError = error;
      _lastWrite = Future<void>.error(error, stack)..ignore();
    }
  }
}
