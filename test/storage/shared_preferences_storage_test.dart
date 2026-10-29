import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zenith/flutter_zenith.dart';
import 'package:flutter_zenith/persistence_shared_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('reads what it wrote', () async {
    final storage = await SharedPreferencesStorage.load();

    expect(storage.read('theme'), isNull);
    await storage.write('theme', 'dark');
    expect(storage.read('theme'), 'dark');
  });

  test('delete removes one key', () async {
    final storage = await SharedPreferencesStorage.load();
    await storage.write('theme', 'dark');

    await storage.delete('theme');

    expect(storage.read('theme'), isNull);
  });

  test('clear removes only the keys this instance wrote', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'locale': 'ro',
      'last_activity': '2026-10-29',
    });
    final storage = await SharedPreferencesStorage.load();
    await storage.write('theme', 'dark');

    await storage.clear();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('theme'), isNull);
    expect(prefs.getString('locale'), 'ro');
    expect(prefs.getString('last_activity'), '2026-10-29');
  });

  test('a PersistedNode over SharedPreferences survives a restart', () async {
    final storage = await SharedPreferencesStorage.load();
    final node = PersistedNode.string(
      key: 'theme',
      defaultValue: 'system',
      storage: storage,
    );

    node.set('dark');
    await node.flush();

    final reopened = PersistedNode.string(
      key: 'theme',
      defaultValue: 'system',
      storage: SharedPreferencesStorage(
        await SharedPreferences.getInstance(),
      ),
    );

    expect(reopened.value, 'dark');
  });
}
