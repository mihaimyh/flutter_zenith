import 'package:shared_preferences/shared_preferences.dart';

import '../../core/zenith/zenith_storage.dart';

/// A [ZenithStorage] backed by `SharedPreferences`.
///
/// Use it directly, or wrapped in [ScopedStorage] to keep one account's values
/// apart from another's on the same device:
///
/// ```dart
/// final backend = await SharedPreferencesStorage.load();
/// final storage = ScopedStorage(backend, scope: userId);
/// final theme = PersistedNode.string(
///   key: 'theme',
///   defaultValue: 'system',
///   storage: storage,
/// );
/// ```
///
/// [PersistedNode] reads synchronously, which is the point: the value is available
/// while the first frame is built instead of after an `await`. `SharedPreferences`
/// loads asynchronously once per process, so await [load] before creating nodes.
class SharedPreferencesStorage implements ZenithStorage {
  /// Wraps an already loaded instance.
  SharedPreferencesStorage(this._prefs);

  /// Loads the backend. Await this before creating the nodes that read from it.
  static Future<SharedPreferencesStorage> load() async =>
      SharedPreferencesStorage(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  /// Keys written through this instance; [clear] is limited to them.
  final Set<String> _written = <String>{};

  @override
  String? read(String key) => _prefs.getString(key);

  @override
  Future<void> write(String key, String value) async {
    _written.add(key);
    await _prefs.setString(key, value);
  }

  @override
  Future<void> delete(String key) async {
    _written.remove(key);
    await _prefs.remove(key);
  }

  /// Deletes the keys this instance wrote.
  ///
  /// `SharedPreferences.clear()` would also remove the locale, the settings cache and
  /// everything else the app keeps, so it is deliberately not used here.
  @override
  Future<void> clear() async {
    final keys = _written.toList(growable: false);
    _written.clear();
    for (final key in keys) {
      await _prefs.remove(key);
    }
  }
}
