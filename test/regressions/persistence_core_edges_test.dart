import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zenith/flutter_zenith.dart';
import 'package:flutter_zenith/src/enterprise/zenith_secure_bytes.dart';
import 'package:flutter_zenith/src/storage/zenith_partitioned_storage.dart';

class GateStorage extends InMemoryStorage {
  final List<String> started = [];
  final List<Completer<void>> gates = [];
  @override
  Future<void> write(String key, String value) async {
    started.add(value);
    final gate = Completer<void>();
    gates.add(gate);
    await gate.future;
    await super.write(key, value);
  }
}

class CallbackSubscriber implements ZenithSubscriber {
  final void Function() callback;
  CallbackSubscriber(this.callback);
  @override
  void onNodeChanged(ZenithNode<dynamic> node) => callback();
}

class RecursiveCommand extends ZenithCommand<int> {
  const RecursiveCommand();
}

void main() {
  test(
    'a same-value write during notification does not suppress persistence',
    () async {
      final storage = InMemoryStorage();
      final node = PersistedNode.integer(
        key: 'key',
        defaultValue: 0,
        storage: storage,
      );
      final subscriber = CallbackSubscriber(() => node.set(node.value));
      node.subscribe(subscriber);
      node.set(1);
      await node.flush();
      expect(storage.read('key'), '1');
    },
  );

  test(
    'nodes sharing backend/key serialize writes and flush reports durability',
    () async {
      final storage = GateStorage();
      final first = PersistedNode.string(
        key: 'key',
        defaultValue: '',
        storage: storage,
      );
      final second = PersistedNode.string(
        key: 'key',
        defaultValue: '',
        storage: storage,
      );
      first.set('one');
      second.set('two');
      await Future<void>.delayed(Duration.zero);
      expect(storage.started, ['one']);
      storage.gates[0].complete();
      await first.flush();
      await Future<void>.delayed(Duration.zero);
      expect(storage.started, ['one', 'two']);
      storage.gates[1].complete();
      await second.flush();
      expect(storage.read('key'), 'two');
    },
  );

  test(
    'async storage errors are observed, flush throws, later writes recover',
    () async {
      final storage = GateStorage();
      final node = PersistedNode.string(
        key: 'key',
        defaultValue: '',
        storage: storage,
      );
      node.set('one');
      final failed = expectLater(node.flush(), throwsStateError);
      await Future<void>.delayed(Duration.zero);
      storage.gates[0].completeError(StateError('disk full'));
      await failed;
      expect(node.persistenceError, isA<StateError>());
      node.set('two');
      await Future<void>.delayed(Duration.zero);
      storage.gates[1].complete();
      await node.flush();
      expect(node.persistenceError, isNull);
      expect(storage.read('key'), 'two');
    },
  );

  test(
    'serializer errors are observable without an uncaught Future error',
    () async {
      final node = PersistedNode<int>(
        key: 'key',
        defaultValue: 0,
        storage: InMemoryStorage(),
        fromStorage: int.parse,
        toStorage: (_) => throw FormatException('bad'),
      );
      node.set(1);
      await Future<void>.delayed(Duration.zero);
      expect(node.persistenceError, isA<FormatException>());
      await expectLater(node.flush(), throwsFormatException);
    },
  );

  test(
    'reentrant mutation persists final value and disposal during notification is safe',
    () async {
      final storage = InMemoryStorage();
      final node = PersistedNode.integer(
        key: 'key',
        defaultValue: 0,
        storage: storage,
      );
      final subscriber = CallbackSubscriber(() {
        if (node.value == 1) node.set(2);
      });
      node.subscribe(subscriber);
      node.set(1);
      await node.flush();
      expect(storage.read('key'), '2');
      node.unsubscribe(subscriber);
      final disposeSubscriber = CallbackSubscriber(node.dispose);
      node.subscribe(disposeSubscriber);
      expect(() => node.set(3), returnsNormally);
      expect(() => node.set(4), returnsNormally);
    },
  );

  test(
    'reset wipes current secure values and releases historical tracking',
    () {
      final container = ZenithContainer();
      final secret = ZenithSecureBytes(Uint8List.fromList([1, 2]));
      container.getOrCreateNode('secret', (_) => secret);
      container.reset(purgeZeroize: true);
      expect(secret.isZeroized, true);
      final replacement = ZenithSecureBytes(Uint8List.fromList([3]));
      container.getOrCreateNode('secret', (_) => replacement);
      container.dispose(purgeZeroize: true);
      expect(replacement.isZeroized, true);
    },
  );

  test(
    'real async recursion is bounded independently of unrelated commands',
    () async {
      final container = ZenithContainer();
      final mediator = ZenithMediator(container);
      mediator.registerCommandHandler<RecursiveCommand, int>((_, _) async {
        await Future<void>.value();
        return mediator.send(const RecursiveCommand());
      });
      await expectLater(
        mediator.send(const RecursiveCommand()),
        throwsStateError,
      );
      mediator.registerCommandHandler<RecursiveCommand, int>((_, _) => 7);
      expect(await mediator.send(const RecursiveCommand()), 7);
      container.dispose();
    },
  );

  test(
    'percent signs, slashes, Unicode and empty keys round-trip independently',
    () async {
      final driver = InMemoryStorageDriver();
      const ids = ['a', 'a/b', 'a%2Fb', 'é', ''];
      const keys = ['', 'b/token', '%2F', 'é'];
      for (final id in ids) {
        final storage = ZenithPartitionedStorage(driver: driver, tenantId: id);
        for (final key in keys) {
          await storage.write(key, '$id|$key');
        }
      }
      for (final id in ids) {
        final storage = ZenithPartitionedStorage(driver: driver, tenantId: id);
        for (final key in keys) {
          expect(await storage.read(key), '$id|$key');
        }
      }
    },
  );
}
