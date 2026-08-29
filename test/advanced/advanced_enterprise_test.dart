import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zenith/zenith_identity.dart';

void main() {
  group('Phase 8: Multi-Isolate IPC, 3-Tier Hierarchy & Route Guards', () {
    test('Test 8.1: 3-Tier Hierarchy allows Workspace swap without destroying UserScope',
        () {
      final manager = ZenithScopeManager();
      final userScope = manager.getOrCreateUserScope('user_mihai');
      final profileNode = userScope.container.getOrCreate(
        const ZenithKey<String>('profile'),
        (_) => 'Mihai Profile',
      );

      // Create Workspace 1 under user.
      final ws1 = userScope.getOrCreateWorkspaceScope('org_devops');
      final teamNode = ws1.container.getOrCreate(
        const ZenithKey<String>('team_data'),
        (_) => 'DevOps Data',
      );

      expect(profileNode.value, equals('Mihai Profile'));
      expect(teamNode.value, equals('DevOps Data'));

      // Switch to Workspace 2.
      userScope.endWorkspaceScope('org_devops');
      final ws2 = userScope.getOrCreateWorkspaceScope('org_personal');
      final personalNode = ws2.container.getOrCreate(
        const ZenithKey<String>('team_data'),
        (_) => 'Personal Data',
      );

      // Workspace 1 data is dead; User data is untouched; Workspace 2 is active.
      expect(() => teamNode.value, throwsA(isA<StateError>()));
      expect(profileNode.value, equals('Mihai Profile'));
      expect(personalNode.value, equals('Personal Data'));
    });

    test('Test 8.2: Two-Phase Scope Drain flushes uncommitted writes before termination',
        () async {
      final manager = ZenithScopeManager();
      final userScope = manager.getOrCreateScope('user_flusher');

      var flushCompleted = false;
      userScope.registerDrainable(ZenithDrainableCallback(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        flushCompleted = true;
      }));

      // Initiate endScope — must await draining phase.
      await manager.endScopeAsync(
        'user_flusher',
        timeout: const Duration(milliseconds: 200),
      );

      expect(flushCompleted, isTrue);
      expect(manager.hasScope('user_flusher'), isFalse);
    });

    test('Test 8.3: Inter-Isolate IPC notifies foreground container to invalidate cache',
        () async {
      const portName = 'zenith_sync_port_test';
      IsolateNameServer.removePortNameMapping(portName);

      final manager = ZenithScopeManager();
      final userScope = manager.getOrCreateScope('user_cache_test');
      final cachedNode = userScope.container.getOrCreate(
        const ZenithKey<List<String>>('items'),
        (_) => ['local_1'],
      );

      var cacheInvalidated = false;
      userScope.listenToInterIsolateInvalidations(portName, onInvalidate: (key) {
        if (key == 'items') {
          cacheInvalidated = true;
          cachedNode.value = ['local_1', 'synced_remote_2'];
        }
      });

      // Simulate background worker isolate firing sync signal.
      final remotePort = IsolateNameServer.lookupPortByName(portName)!;
      remotePort.send(ZenithInvalidateMessage(
        tenantId: 'user_cache_test',
        nodeKey: 'items',
      ));

      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(cacheInvalidated, isTrue);
      expect(cachedNode.value, equals(['local_1', 'synced_remote_2']));

      // Cleanup — userScope.dispose() closes the IPC listener.
      userScope.dispose();
    });

    test('Test 8.4: Declarative Route Guard denies navigation and returns redirect route',
        () {
      const authService = ZenithAuthorizationService();
      final billingPolicy = ZenithPolicy(
        name: 'MustBeAdmin',
        requirements: [RequireRole('admin')],
      );

      const freeUserContext = UserSecurityContext(
        isAuthenticated: true,
        roles: ['viewer'],
      );

      final redirectPath = ZenithRouteGuard.evaluate(
        context: freeUserContext,
        policy: billingPolicy,
        authService: authService,
        deniedRedirectPath: '/upsell-paywall',
      );

      expect(redirectPath, equals('/upsell-paywall'));
    });
  });
}
