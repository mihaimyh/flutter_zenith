import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zenith/zenith_identity.dart';

void main() {
  group('Phase 3: Multi-Tenant Partitioned Storage & Outbox', () {
    test('Test 3.1: Disk storage keys are strictly isolated per tenant',
        () async {
      final mockDriver = InMemoryStorageDriver();
      final storageA =
          ZenithPartitionedStorage(driver: mockDriver, tenantId: 'user_a');
      final storageB =
          ZenithPartitionedStorage(driver: mockDriver, tenantId: 'user_b');

      await storageA.write('draft_document', 'Sensitive Content from User A');
      final readFromB = await storageB.read('draft_document');

      expect(readFromB, isNull);
      expect(
        await mockDriver.rawRead('tenants/user_a/draft_document'),
        equals('Sensitive Content from User A'),
      );
    });

    test('Test 3.2: Offline Outbox freezes inactive tenant queue on account switch',
        () async {
      final outbox = ZenithOutboxEngine();

      outbox.enqueue(
        tenantId: 'user_a',
        action: 'UpdateBio',
        payload: {'bio': 'New Bio'},
      );
      outbox.setActiveTenant('user_b');

      var userADispatched = false;

      await outbox.flush((mutation) async {
        if (mutation.tenantId == 'user_a') userADispatched = true;
      });

      expect(
        userADispatched,
        isFalse,
        reason: "User A's outbox must not flush under User B's session.",
      );
      expect(outbox.pendingCount('user_a'), equals(1));

      outbox.setActiveTenant('user_a');
      await outbox.flush((mutation) async {
        if (mutation.tenantId == 'user_a') userADispatched = true;
      });

      expect(userADispatched, isTrue);
      expect(outbox.pendingCount('user_a'), equals(0));
    });

    test('Test 3.3: Outbox continues flushing after individual mutation failure',
        () async {
      final outbox = ZenithOutboxEngine();
      outbox.setActiveTenant('user_a');

      outbox.enqueue(
        tenantId: 'user_a',
        action: 'FailingAction',
        payload: {},
        maxRetries: 2,
      );
      outbox.enqueue(
        tenantId: 'user_a',
        action: 'SucceedingAction',
        payload: {},
      );

      final dispatched = <String>[];

      await outbox.flush((mutation) async {
        if (mutation.action == 'FailingAction') {
          throw Exception('503 Service Unavailable');
        }
        dispatched.add(mutation.action);
      });

      // Subsequent mutation succeeded despite first one failing
      expect(dispatched, contains('SucceedingAction'));
      expect(outbox.pendingCount('user_a'), equals(1));

      // Immediate re-flush without backoff elapsed is skipped
      var immediateAttempts = 0;
      await outbox.flush((mutation) async {
        immediateAttempts++;
      });
      expect(immediateAttempts, equals(0), reason: 'Must respect backoff window');

      // Flush with ignoreBackoff to trigger maxRetries threshold
      await outbox.flush(
        (mutation) async {
          if (mutation.action == 'FailingAction') {
            throw Exception('503 Service Unavailable');
          }
        },
        ignoreBackoff: true,
      );

      // Failing action moved to dead letter queue after exceeding maxRetries
      expect(outbox.deadLetterCount('user_a'), equals(1));
      expect(outbox.pendingCount('user_a'), equals(0));
    });
  });
}
