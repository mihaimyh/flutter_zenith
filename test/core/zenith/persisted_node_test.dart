import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zenith/flutter_zenith.dart';

void main() {
  group('InMemoryStorage', () {
    test('read, write, delete, clear operations', () async {
      final storage = InMemoryStorage();

      expect(storage.read('token'), isNull);

      await storage.write('token', 'secret_abc');
      expect(storage.read('token'), 'secret_abc');

      await storage.delete('token');
      expect(storage.read('token'), isNull);

      await storage.write('theme', 'dark');
      await storage.clear();
      expect(storage.read('theme'), isNull);
    });
  });

  group('PersistedNode', () {
    test('initializes with defaultValue when storage has no entry', () {
      final storage = InMemoryStorage();
      final node = PersistedNode.string(
        key: 'username',
        defaultValue: 'guest',
        storage: storage,
      );

      expect(node.value, 'guest');
    });

    test('initializes with stored value when entry exists', () async {
      final storage = InMemoryStorage();
      await storage.write('username', 'alice');

      final node = PersistedNode.string(
        key: 'username',
        defaultValue: 'guest',
        storage: storage,
      );

      expect(node.value, 'alice');
    });

    test('set() mutates node value and writes to storage', () async {
      final storage = InMemoryStorage();
      final node = PersistedNode.string(
        key: 'jwt_token',
        defaultValue: '',
        storage: storage,
      );

      node.set('header_token_123');
      expect(node.value, 'header_token_123');

      // Async write completes
      await Future<void>.delayed(Duration.zero);
      expect(storage.read('jwt_token'), 'header_token_123');
    });

    test('PersistedNode.integer helper serializes and restores integers', () async {
      final storage = InMemoryStorage();
      await storage.write('counter', '42');

      final node = PersistedNode.integer(
        key: 'counter',
        defaultValue: 0,
        storage: storage,
      );

      expect(node.value, 42);

      node.set(100);
      await Future<void>.delayed(Duration.zero);
      expect(storage.read('counter'), '100');
    });

    test('PersistedNode.boolean helper serializes and restores booleans', () async {
      final storage = InMemoryStorage();
      final node = PersistedNode.boolean(
        key: 'dark_mode',
        defaultValue: false,
        storage: storage,
      );

      expect(node.value, isFalse);

      node.set(true);
      await Future<void>.delayed(Duration.zero);
      expect(storage.read('dark_mode'), 'true');
    });

    test('custom complex object serialization', () async {
      final storage = InMemoryStorage();
      final node = PersistedNode<List<String>>(
        key: 'tags',
        defaultValue: const [],
        storage: storage,
        toStorage: (tags) => tags.join(','),
        fromStorage: (raw) => raw.isEmpty ? [] : raw.split(','),
      );

      expect(node.value, isEmpty);

      node.set(['flutter', 'zenith']);
      await Future<void>.delayed(Duration.zero);
      expect(storage.read('tags'), 'flutter,zenith');
    });
  });
}
