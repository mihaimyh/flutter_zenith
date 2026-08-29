import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zenith/zenith_identity.dart';

void main() {
  group('Phase 2: Identity State Machine & Migration', () {
    test(
        'Test 2.1: Anonymous to Authenticated Data Migration transfers state cleanly',
        () async {
      final coordinator = ZenithIdentityCoordinator();
      await coordinator.signInAnonymously(anonId: 'anon_123');

      final anonScope = coordinator.currentScope!;
      anonScope.container.getOrCreate(
        const ZenithKey<List<String>>('cart'),
        (_) => ['item_1', 'item_2'],
      );

      var migrationRan = false;
      await coordinator.upgradeAnonymousAccount(
        newSession: 'user_real_456',
        onMigrate: (fromContainer, toContainer) async {
          final oldCart =
              fromContainer.maybeNode<List<String>>(const ZenithKey<List<String>>('cart'))!.value;
          final newCartNode = toContainer.getOrCreate<List<String>>(
            const ZenithKey<List<String>>('cart'),
            (_) => [],
          );
          newCartNode.value = List.from(oldCart)..add('bonus_signup_item');
          migrationRan = true;
        },
      );

      expect(migrationRan, isTrue);
      expect(coordinator.state, isA<AuthAuthenticated<String>>());
      expect(coordinator.currentScope!.id, equals('user_real_456'));

      final targetCart = coordinator.currentScope!.container
          .maybeNode<List<String>>(const ZenithKey<List<String>>('cart'))!
          .value;
      expect(targetCart, equals(['item_1', 'item_2', 'bonus_signup_item']));
      expect(coordinator.hasScope('anon_123'), isFalse);
    });

    test('Test 2.2: Migration IO Failure aborts swap and preserves anonymous state',
        () async {
      final coordinator = ZenithIdentityCoordinator();
      await coordinator.signInAnonymously(anonId: 'anon_123');

      await expectLater(
        () => coordinator.upgradeAnonymousAccount(
          newSession: 'user_real_456',
          onMigrate: (from, to) async =>
              throw Exception('Network timeout during cart merge'),
        ),
        throwsA(isA<ZenithMigrationException>()),
      );

      expect(coordinator.currentScope!.id, equals('anon_123'));
      expect(coordinator.hasScope('anon_123'), isTrue);
      expect(coordinator.hasScope('user_real_456'), isFalse);
    });

    test(
        'Test 2.3: Biometric Lock preserves container and pauses active stream nodes',
        () async {
      final coordinator = ZenithIdentityCoordinator();
      await coordinator.signIn('user_session_1');

      final scope = coordinator.currentScope!;
      var streamEventsReceived = 0;
      final counterNode = scope.container.getOrCreate<int>(
        const ZenithKey<int>('counter_stream'),
        (_) => 0,
      );
      // Use a simple subscription instead of a stream for this test.
      final sub = _MockSubscriber(() => streamEventsReceived++);
      counterNode.subscribe(sub);

      coordinator.lockSession();

      expect(coordinator.state, isA<AuthLocked>());
      expect(coordinator.hasScope('user_session_1'), isTrue);
      expect(scope.isDormant, isTrue);

      await coordinator.unlockSession();
      expect(scope.isDormant, isFalse);
      counterNode.unsubscribe(sub);
    });
  });
}

class _MockSubscriber implements ZenithSubscriber {
  final void Function() _onChanged;
  _MockSubscriber(this._onChanged);

  @override
  void onNodeChanged(ZenithNode<dynamic> node) => _onChanged();
}
