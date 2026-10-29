import 'dart:convert';
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

  /// Set by [set]: the value was decided in this process, so a backend attached
  /// later must not replace it with an older cache.
  bool _decided = false;

  /// Latest write/serialization failure, cleared after a successful write.
  Object? get persistenceError => _persistenceError;

  /// Awaits this node's latest accepted write and propagates its failure.
  /// Call before ending a scope when durability is required.
  Future<void> flush() => _lastWrite;

  /// The key used for storage lookup.
  final String key;

  /// The value used when storage has no usable entry. Kept so [attachStorage] can
  /// tell a node that never decided from one that did.
  final T _defaultValue;

  /// The value used when storage has no usable entry.
  T get defaultValue => _defaultValue;

  ZenithStorage _storage;

  /// The storage backend powering this node. Replaced by [attachStorage].
  ZenithStorage get storage => _storage;

  /// Serializer callback converting [T] to a [String].
  final String Function(T value) toStorage;

  /// Deserializer callback parsing [String] back into [T].
  final T Function(String raw) fromStorage;

  /// Creates a [PersistedNode] with custom serialization callbacks.
  PersistedNode({
    required this.key,
    required T defaultValue,
    required ZenithStorage storage,
    required this.toStorage,
    required this.fromStorage,
  }) : _defaultValue = defaultValue,
       _storage = storage,
       super(_resolveInitial(key, defaultValue, storage, fromStorage));

  static T _resolveInitial<T>(
    String key,
    T defaultValue,
    ZenithStorage storage,
    T Function(String raw) fromStorage,
  ) {
    return _read(key, storage, fromStorage) ?? defaultValue;
  }

  /// Reads [key], or `null` when it is absent or unusable. A corrupt entry is a
  /// cache miss, never an exception on launch.
  static T? _read<T>(
    String key,
    ZenithStorage storage,
    T Function(String raw) fromStorage,
  ) {
    final raw = storage.read(key);
    if (raw == null) {
      return null;
    }
    try {
      return fromStorage(raw);
    } catch (_) {
      return null;
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

  /// Helper for values stored as a JSON object.
  ///
  /// ```dart
  /// final profile = PersistedNode.json<Profile>(
  ///   key: 'profile',
  ///   defaultValue: const Profile.guest(),
  ///   storage: storage,
  ///   toJson: (value) => value.toJson(),
  ///   fromJson: Profile.fromJson,
  /// );
  /// ```
  static PersistedNode<T> json<T>({
    required String key,
    required T defaultValue,
    required ZenithStorage storage,
    required Map<String, dynamic> Function(T value) toJson,
    required T Function(Map<String, dynamic> json) fromJson,
  }) {
    return PersistedNode<T>(
      key: key,
      defaultValue: defaultValue,
      storage: storage,
      toStorage: (value) => jsonEncode(toJson(value)),
      fromStorage: (raw) {
        final decoded = jsonDecode(raw);
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException('persisted value is not a json object');
        }
        return fromJson(decoded);
      },
    );
  }

  /// Switches the backend at runtime.
  ///
  /// A node is often created before the backend is known — the key may need an
  /// account id that only auth can supply. Attaching later must not lose a value
  /// already decided in this process, and must not resurrect an older cache over
  /// one:
  ///
  /// * nothing has been [set] yet and the new backend has a readable value →
  ///   adopt it;
  /// * otherwise keep the current value and write it to the new backend, so the
  ///   decision is durable.
  ///
  /// Writes already accepted by the previous backend are not cancelled.
  void attachStorage(ZenithStorage storage) {
    if (identical(storage, _storage)) return;
    _storage = storage;

    if (!_decided) {
      final cached = _read(key, storage, fromStorage);
      if (cached != null) {
        set(cached);
        return;
      }
    }
    _persist(value);
  }

  @override
  void set(T newValue) {
    if (isDisposed) return;
    _decided = true;
    final oldValue = value;
    if (oldValue == newValue) return;
    final generation = ++_generation;
    super.set(newValue);
    // A subscriber may dispose this node or synchronously write a newer value.
    if (isDisposed || generation != _generation || value == oldValue) return;
    _persist(newValue, generation);
  }

  void _persist(T snapshot, [int? generation]) {
    final writeGeneration = generation ?? _generation;
    try {
      final serialized = toStorage(snapshot);
      final pending = _writes[_storage] ??= {};
      final previous = pending[key] ?? Future<void>.value();
      final write = previous
          .then<void>((_) {}, onError: (Object _, StackTrace _) {})
          .then((_) => _storage.write(key, serialized));
      pending[key] = write;
      _lastWrite = write;
      write.then(
        (_) {
          if (writeGeneration == _generation) _persistenceError = null;
          if (identical(pending[key], write)) pending.remove(key);
        },
        onError: (Object error, StackTrace stack) {
          if (writeGeneration == _generation) _persistenceError = error;
          if (identical(pending[key], write)) pending.remove(key);
        },
      );
    } catch (error, stack) {
      _persistenceError = error;
      _lastWrite = Future<void>.error(error, stack)..ignore();
    }
  }
}
