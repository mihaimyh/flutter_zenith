import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zenith/zenith_identity.dart';

void main() {
  group('Phase 1: ZenithScopeManager & Scope Isolation', () {
    test('Test 1.1: Scope Disposal completely isolates and frees tenant nodes',
        () {
      final manager = ZenithScopeManager();
      final userAScope = manager.getOrCreateScope('user_a');
      final node = userAScope.container
          .getOrCreate(const ZenithKey<String>('profile'), (_) => 'Alice');

      expect(node.value, equals('Alice'));
      manager.endScope('user_a');

      expect(manager.hasScope('user_a'), isFalse);
      expect(() => node.value, throwsA(isA<StateError>()));
    });

    test('Test 1.2: Captive Dependency Detection throws exception', () {
      final manager = ZenithScopeManager();
      final userScope = manager.getOrCreateScope('user_a');

      const userNodeKey = ZenithKey<String>('user_token');

      // Register the scoped key in the user scope.
      userScope.register(userNodeKey, () => 'secret_token',
          lifetime: ZenithLifetime.scoped);

      const rootServiceKey = ZenithKey<String>('root_service');

      // Attempting to register a singleton that resolves a scoped key must throw.
      expect(
        () => manager.appScope.register(
          rootServiceKey,
          () {
            // Direct container access inside singleton factory is intercepted by Zone guard!
            return userScope.container.maybeNode<String>(userNodeKey)?.value ??
                '';
          },
          lifetime: ZenithLifetime.singleton,
        ),
        throwsA(isA<ZenithCaptiveDependencyException>()),
      );
    });

    test(
        'Test 1.3: Concurrency Race on Rapid User Swap cancels stale mutations',
        () async {
      final manager = ZenithScopeManager();
      final userAScope = manager.getOrCreateScope('user_a');
      final stateNode = userAScope.container
          .getOrCreate(const ZenithKey<String>('data'), (_) => 'initial');

      var taskExecutedAfterDisposal = false;

      userAScope.runWithToken((token) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        // Only mutate if the scope/token is still live.
        if (!token.isCancelled) {
          stateNode.value = 'mutated_by_user_a';
          taskExecutedAfterDisposal = true;
        }
      });

      // User A logs out; User B logs in before the future finishes.
      manager.endScope('user_a');
      final userBScope = manager.getOrCreateScope('user_b');
      final userBNode = userBScope.container
          .getOrCreate(const ZenithKey<String>('data'), (_) => 'user_b_clean');

      await Future<void>.delayed(const Duration(milliseconds: 70));

      expect(userBNode.value, equals('user_b_clean'));
      expect(taskExecutedAfterDisposal, isFalse);
    });
  });
}
