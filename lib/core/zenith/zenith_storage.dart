/// Abstract storage interface for state persistence in `flutter_zenith`.
///
/// Implement this interface to connect [PersistedNode] to key-value backends
/// such as `SharedPreferences`, `flutter_secure_storage`, `Hive`, or SQLite.
///
/// Use [InMemoryStorage] for unit tests, ephemeral caches, or mock environments.
abstract class ZenithStorage {
  /// Reads the string value associated with [key] synchronously.
  ///
  /// Returns `null` if [key] is not present.
  String? read(String key);

  /// Writes [value] to [key] in storage.
  Future<void> write(String key, String value);

  /// Deletes the entry at [key].
  Future<void> delete(String key);

  /// Clears all stored key-value pairs.
  Future<void> clear();
}

/// An in-memory implementation of [ZenithStorage] backed by a Dart [Map].
///
/// Useful for unit testing, fast mock storage, or volatile session caches.
class InMemoryStorage implements ZenithStorage {
  final Map<String, String> _map = <String, String>{};

  @override
  String? read(String key) => _map[key];

  @override
  Future<void> write(String key, String value) async {
    _map[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _map.remove(key);
  }

  @override
  Future<void> clear() async {
    _map.clear();
  }
}
/// A synchronous, per-scope view over a shared [ZenithStorage].
///
/// [ZenithPartitionedStorage] (in `zenith_identity`) offers the same isolation for
/// async backends, but a [PersistedNode] reads synchronously at construction, so it
/// needs a synchronous view: one backend on the device, one namespace per account.
///
/// ```dart
/// final storage = ScopedStorage(prefs, scope: userId);
/// final tier = PersistedNode.string(key: "tier", defaultValue: "explorer", storage: storage);
/// ```
class ScopedStorage implements ZenithStorage {
  /// Wraps [inner], namespacing every key under [scope].
  ScopedStorage(this._inner, {required this.scope});

  final ZenithStorage _inner;

  /// The account, tenant or session this view belongs to.
  final String scope;

  /// Keys read or written through this view. [clear] is limited to them, because
  /// [ZenithStorage] cannot enumerate and clearing the backend would wipe every
  /// other scope.
  final Set<String> _touched = <String>{};

  String _namespace(String key) =>
      'scope/${Uri.encodeComponent(scope)}/${Uri.encodeComponent(key)}';

  @override
  String? read(String key) {
    _touched.add(key);
    return _inner.read(_namespace(key));
  }

  @override
  Future<void> write(String key, String value) {
    _touched.add(key);
    return _inner.write(_namespace(key), value);
  }

  @override
  Future<void> delete(String key) {
    _touched.remove(key);
    return _inner.delete(_namespace(key));
  }

  @override
  Future<void> clear() async {
    final keys = _touched.toList(growable: false);
    _touched.clear();
    for (final key in keys) {
      await _inner.delete(_namespace(key));
    }
  }
}
