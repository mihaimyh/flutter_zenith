import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zenith/zenith_identity.dart';

void main() {
  group('Phase 7: Enterprise Compliance & Physical Isolation', () {
    test(
        'Test 7.1: Cryptographic Zeroization wipes sensitive memory buffers on disposal',
        () {
      final manager = ZenithScopeManager();
      final userScope = manager.getOrCreateScope('user_secure');

      final rawSecret = Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF]);
      final secureToken = ZenithSecureBytes(rawSecret);

      // Instantiate the secure token directly via standard container getOrCreate (no manual scope.register required).
      userScope.container.getOrCreate<ZenithSecureBytes>(
        const ZenithKey<ZenithSecureBytes>('token'),
        (_) => secureToken,
      );

      expect(secureToken.bytes, equals([0xDE, 0xAD, 0xBE, 0xEF]));

      manager.endScope('user_secure', purgeZeroize: true);

      expect(secureToken.bytes, equals([0x00, 0x00, 0x00, 0x00]));
      expect(secureToken.isZeroized, isTrue);
    });

    test(
        'Test 7.1b: Eager Zeroization wipes replaced sensitive buffer immediately on mutation',
        () {
      final secret1 = ZenithSecureBytes(Uint8List.fromList([1, 2, 3, 4]));
      final secret2 = ZenithSecureBytes(Uint8List.fromList([5, 6, 7, 8]));

      final node = ZenithNode<ZenithSecureBytes>(secret1);

      expect(secret1.isZeroized, isFalse);

      // Mutate node with a new buffer — secret1 must be zeroized immediately
      node.value = secret2;

      expect(secret1.isZeroized, isTrue);
      expect(secret1.bytes, equals([0, 0, 0, 0]));
      expect(secret2.isZeroized, isFalse);
    });

    test(
        'Test 7.2: Physical Database File Isolation closes file locks on switch',
        () async {
      final manager = ZenithScopeManager();
      final pool = InMemoryDatabasePool(baseDir: '/test_db');

      final userAScope = manager.getOrCreateScope('user_a');
      final dbHandleA =
          await pool.acquireConnection(userAScope.id, scope: userAScope);

      expect(dbHandleA.filePath, equals('/test_db/tenants/user_a/data.db'));
      expect(dbHandleA.isOpen, isTrue);

      await manager.endScopeAsync('user_a');
      expect(dbHandleA.isOpen, isFalse);

      final userBScope = manager.getOrCreateScope('user_b');
      final dbHandleB = await pool.acquireConnection(userBScope.id);

      expect(dbHandleB.filePath, equals('/test_db/tenants/user_b/data.db'));
      expect(dbHandleB.isOpen, isTrue);
      await pool.disposeAll();
    });

    test(
        'Test 7.3: Distributed Back-Channel Revocation terminates session and triggers alert',
        () async {
      final coordinator = ZenithIdentityCoordinator();
      await coordinator.signIn('user_enterprise_1');

      var revocationReasonReceived = '';
      coordinator.onSecurityRevocation((reason) {
        revocationReasonReceived = reason.name;
      });

      await coordinator.ingestRemoteRevocation(
        tenantId: 'user_enterprise_1',
        reason: RevocationReason.sessionInvalidatedByAdmin,
      );

      expect(coordinator.state, isA<AuthUnauthenticated>());
      expect(coordinator.hasScope('user_enterprise_1'), isFalse);
      expect(revocationReasonReceived, equals('sessionInvalidatedByAdmin'));
    });

    test(
        'Test 7.4: Headless Isolate Bootstrap initializes tenant without Flutter bindings',
        () async {
      final headlessScope = await ZenithScopeManager.bootstrapHeadless(
        tenantId: 'user_worker_1',
        storageFactory: (tenant) => InMemoryStorageDriver(),
      );

      final taskNode = headlessScope.container.getOrCreate(
        const ZenithKey<String>('task_status'),
        (_) => 'running',
      );
      expect(taskNode.value, equals('running'));

      await headlessScope.drainAndDispose();
      expect(headlessScope.isDisposed, isTrue);
    });
  });
}
