/// A raw storage driver with async read/write, used by
/// [ZenithPartitionedStorage] as the physical backing.
///
/// Implementations may wrap SharedPreferences, encrypted secure storage,
/// SQLite, Hive, or an in-memory map (for tests).
abstract class StorageDriver {
  /// Reads the value at [key], or `null` if absent.
  Future<String?> read(String key);

  /// Writes [value] at [key].
  Future<void> write(String key, String value);

  /// Deletes the entry at [key].
  Future<void> delete(String key);
}

/// An in-memory [StorageDriver] backed by a plain Dart [Map].
///
/// Provides direct [rawRead] / [rawWrite] access for test assertions (e.g.
/// verifying that key isolation is enforced at the prefix level).
class InMemoryStorageDriver implements StorageDriver {
  final Map<String, String> _store = {};

  @override
  Future<String?> read(String key) async => _store[key];

  @override
  Future<void> write(String key, String value) async {
    _store[key] = value;
  }

  @override
  Future<void> delete(String key) async => _store.remove(key);

  /// Reads [key] from the raw underlying store — bypasses any namespacing.
  ///
  /// Use this in tests to assert that namespaced keys were written correctly.
  Future<String?> rawRead(String key) async => _store[key];
}

/// A tenant-namespaced storage wrapper.
///
/// All keys passed to [read] / [write] are prefixed with
/// `tenants/{tenantId}/` so that data from different users can never collide
/// in the same underlying [StorageDriver].
///
/// ```dart
/// final driver = InMemoryStorageDriver();
/// final storageA = ZenithPartitionedStorage(driver: driver, tenantId: 'user_a');
/// final storageB = ZenithPartitionedStorage(driver: driver, tenantId: 'user_b');
///
/// await storageA.write('token', 'abc');
/// expect(await storageB.read('token'), isNull); // Isolation verified.
/// ```
class ZenithPartitionedStorage {
  /// The backing storage driver shared by all tenants.
  final StorageDriver driver;

  /// The tenant id used to namespace all keys.
  final String tenantId;

  /// Creates a [ZenithPartitionedStorage] for [tenantId] backed by [driver].
  ZenithPartitionedStorage({required this.driver, required this.tenantId});

  String _namespace(String key) => 'tenants/$tenantId/$key';

  /// Reads the value for [key] scoped to this tenant, or `null` if absent.
  Future<String?> read(String key) => driver.read(_namespace(key));

  /// Writes [value] for [key] scoped to this tenant.
  Future<void> write(String key, String value) =>
      driver.write(_namespace(key), value);

  /// Deletes the entry for [key] scoped to this tenant.
  Future<void> delete(String key) => driver.delete(_namespace(key));
}
