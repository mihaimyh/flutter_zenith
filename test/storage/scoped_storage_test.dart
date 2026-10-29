import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zenith/flutter_zenith.dart';

/// `ScopedStorage` is the synchronous answer to "one backend, one account": the
/// async `ZenithPartitionedStorage` cannot back a `PersistedNode`, which reads
/// synchronously at construction.
void main() {
  group('ScopedStorage', () {
    test('two scopes over one backend never see each other', () async {
      final backend = InMemoryStorage();
      final a = ScopedStorage(backend, scope: 'user_a');
      final b = ScopedStorage(backend, scope: 'user_b');

      await a.write('tier', 'fluent');

      expect(a.read('tier'), 'fluent');
      expect(b.read('tier'), isNull);
      // The value really lives in the shared backend, under a scoped key.
      expect(backend.read('scope/user_a/tier'), 'fluent');
    });

    test('delete removes only the scoped key', () async {
      final backend = InMemoryStorage();
      final a = ScopedStorage(backend, scope: 'user_a');
      final b = ScopedStorage(backend, scope: 'user_b');

      await a.write('tier', 'fluent');
      await b.write('tier', 'explorer');

      await a.delete('tier');

      expect(a.read('tier'), isNull);
      expect(b.read('tier'), 'explorer');
    });

    test('clear drops the keys touched through this scope only', () async {
      final backend = InMemoryStorage();
      final a = ScopedStorage(backend, scope: 'user_a');
      final b = ScopedStorage(backend, scope: 'user_b');

      await a.write('tier', 'fluent');
      await a.write('theme', 'dark');
      await b.write('tier', 'explorer');

      await a.clear();

      expect(a.read('tier'), isNull);
      expect(a.read('theme'), isNull);
      expect(b.read('tier'), 'explorer');
    });

    test('scope ids are encoded, so a slash cannot escape its scope', () async {
      final backend = InMemoryStorage();
      final sneaky = ScopedStorage(backend, scope: 'user_a');
      final other = ScopedStorage(backend, scope: '../user_a');

      await other.write('tier', 'fluent');

      expect(sneaky.read('tier'), isNull);
      expect(backend.read('../user_a/tier'), isNull);
    });

    test('a PersistedNode restores through the scope', () async {
      final backend = InMemoryStorage();
      final storage = ScopedStorage(backend, scope: 'user_a');

      // A previous process wrote under the same scope.
      await backend.write('scope/user_a/theme', 'dark');

      final theme = PersistedNode.string(
        key: 'theme',
        defaultValue: 'system',
        storage: storage,
      );

      expect(theme.value, 'dark');
    });
  });
}
