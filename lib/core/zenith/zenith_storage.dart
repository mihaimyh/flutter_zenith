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
