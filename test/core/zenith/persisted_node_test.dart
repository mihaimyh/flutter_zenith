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

    test(
      'PersistedNode.integer helper serializes and restores integers',
      () async {
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
      },
    );

    test(
      'PersistedNode.boolean helper serializes and restores booleans',
      () async {
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
      },
    );

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

  group('PersistedNode.json', () {
    test('round-trips a map-backed value', () async {
      final storage = InMemoryStorage();
      final node = PersistedNode.json<_Profile>(
        key: 'profile',
        defaultValue: const _Profile(name: "guest", score: 0),
        storage: storage,
        toJson: (value) => value.toJson(),
        fromJson: _Profile.fromJson,
      );

      node.set(const _Profile(name: 'alice', score: 42));
      await node.flush();

      final reopened = PersistedNode.json<_Profile>(
        key: 'profile',
        defaultValue: const _Profile(name: "guest", score: 0),
        storage: storage,
        toJson: (value) => value.toJson(),
        fromJson: _Profile.fromJson,
      );

      expect(reopened.value.name, 'alice');
      expect(reopened.value.score, 42);
    });

    test('a payload that is not a json object is a cache miss', () async {
      final storage = InMemoryStorage();
      await storage.write('profile', '[1,2,3]');

      final node = PersistedNode.json<_Profile>(
        key: 'profile',
        defaultValue: const _Profile(name: "guest", score: 0),
        storage: storage,
        toJson: (value) => value.toJson(),
        fromJson: _Profile.fromJson,
      );

      expect(node.value.name, 'guest');
    });

    test('a decoder that rejects the payload is a cache miss', () async {
      final storage = InMemoryStorage();
      await storage.write('profile', '{"name":""}');

      final node = PersistedNode.json<_Profile>(
        key: 'profile',
        defaultValue: const _Profile(name: "guest", score: 0),
        storage: storage,
        toJson: (value) => value.toJson(),
        fromJson: _Profile.fromJson,
      );

      expect(node.value.name, 'guest');
    });
  });

  group('PersistedNode.attachStorage', () {
    test('hydrates from a backend attached after construction', () async {
      final cache = InMemoryStorage();
      await cache.write('tier', 'fluent');

      final node = PersistedNode.string(
        key: 'tier',
        defaultValue: 'explorer',
        storage: InMemoryStorage(),
      );
      expect(node.value, 'explorer');

      node.attachStorage(cache);

      expect(node.value, 'fluent');
    });

    test('a scan decided before the attach wins over a stale cache', () async {
      final cache = InMemoryStorage();
      await cache.write('tier', 'fluent');

      final node = PersistedNode.string(
        key: 'tier',
        defaultValue: 'explorer',
        storage: InMemoryStorage(),
      );
      node.set('explorer');

      node.attachStorage(cache);
      await node.flush();

      expect(node.value, 'explorer');
      expect(cache.read('tier'), 'explorer');
    });

    test('writes later changes to the attached backend, not the old one', () async {
      final old = InMemoryStorage();
      final cache = InMemoryStorage();
      final node = PersistedNode.string(
        key: 'tier',
        defaultValue: 'explorer',
        storage: old,
      );

      node.attachStorage(cache);
      node.set('fluent');
      await node.flush();

      expect(cache.read('tier'), 'fluent');
      expect(old.read('tier'), isNull);
    });

    test('a corrupt payload is ignored and the live value is written', () async {
      final cache = InMemoryStorage();
      await cache.write('tier', '\u0000not-valid');

      final node = PersistedNode<String>(
        key: 'tier',
        defaultValue: 'explorer',
        storage: InMemoryStorage(),
        toStorage: (value) => value,
        fromStorage: (raw) {
          if (raw.contains('not-valid')) throw const FormatException('bad');
          return raw;
        },
      );

      node.attachStorage(cache);
      await node.flush();

      expect(node.value, 'explorer');
      expect(cache.read('tier'), 'explorer');
    });

    test('adopting the stored value wins even after a decision, for a new scope', () async {
      // Account switch: the cache belongs to the next account, so "fresher in this
      // process" does not apply to it.
      final nextAccount = InMemoryStorage();
      await nextAccount.write('tier', 'fluent');

      final node = PersistedNode.string(
        key: 'tier',
        defaultValue: 'explorer',
        storage: InMemoryStorage(),
      );
      node.set('explorer');

      node.attachStorage(nextAccount, adoptStoredValue: true);

      expect(node.value, 'fluent');
    });

    test('adopting an empty backend keeps the decided value', () async {
      final nextAccount = InMemoryStorage();
      final node = PersistedNode.string(
        key: 'tier',
        defaultValue: 'explorer',
        storage: InMemoryStorage(),
      );
      node.set('fluent');

      node.attachStorage(nextAccount, adoptStoredValue: true);
      await node.flush();

      expect(node.value, 'fluent');
      expect(nextAccount.read('tier'), 'fluent');
    });

    test('attaching the same backend twice is a no-op', () async {
      final cache = InMemoryStorage();
      await cache.write('tier', 'fluent');

      final node = PersistedNode.string(
        key: 'tier',
        defaultValue: 'explorer',
        storage: InMemoryStorage(),
      );

      node.attachStorage(cache);
      node.set('explorer');
      node.attachStorage(cache);

      expect(node.value, 'explorer');
    });
  });
}

class _Profile {
  const _Profile({required this.name, required this.score});

  final String name;
  final int score;

  Map<String, dynamic> toJson() => {
    'name': name,
    'score': score,
  };

  factory _Profile.fromJson(Map<String, dynamic> json) {
    final name = json['name'];
    final score = json['score'];
    if (name is! String || name.isEmpty || score is! int) {
      throw const FormatException('invalid profile');
    }
    return _Profile(name: name, score: score);
  }
}