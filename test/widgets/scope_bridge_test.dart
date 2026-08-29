import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zenith/zenith_identity.dart';

void main() {
  group('Phase 5: Route Scope Tunneling & Revocation', () {
    testWidgets(
        'Test 5.1: Modal Bottom Sheet inherits scoped container dependencies',
        (tester) async {
      final manager = ZenithScopeManager();
      final userScope = manager.getOrCreateScope('user_a');
      const scopedKey = ZenithKey<String>('user_alias');
      userScope.container
          .getOrCreate<String>(scopedKey, (_) => 'Mihai');

      await tester.pumpWidget(
        MaterialApp(
          home: ZenithScopeProvider(
            scope: userScope,
            child: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  context.zenithShowModalBottomSheet<void>(
                    builder: (sheetContext) =>
                        Text('Resolved: ${sheetContext.zenith(scopedKey)}'),
                  );
                },
                child: const Text('OPEN_SHEET'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('OPEN_SHEET'));
      await tester.pumpAndSettle();

      expect(find.text('Resolved: Mihai'), findsOneWidget);
    });

    testWidgets(
        'Test 5.2: Revocation drains navigation tree cleanly before container disposal',
        (tester) async {
      final coordinator = ZenithIdentityCoordinator();
      await coordinator.signIn('user_a');

      var containerDisposed = false;
      coordinator.currentScope!.onDispose(() => containerDisposed = true);

      await tester.pumpWidget(
        MaterialApp(
          home: ZenithAuthScope(
            coordinator: coordinator,
            authenticatedBuilder: (context, scope) => Scaffold(
              body: Builder(
                builder: (ctx) => ElevatedButton(
                  onPressed: () => Navigator.of(ctx).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const Text('Deep Screen'),
                    ),
                  ),
                  child: const Text('PUSH_DEEP'),
                ),
              ),
            ),
            unauthenticatedBuilder: (context) =>
                const Text('LOGIN_SCREEN'),
          ),
        ),
      );

      await tester.pump();
      expect(find.text('PUSH_DEEP'), findsOneWidget);

      await coordinator.signOut();
      await tester.pumpAndSettle();

      expect(find.text('LOGIN_SCREEN'), findsOneWidget);
      expect(containerDisposed, isTrue);
      expect(tester.takeException(), isNull);
    });
  });
}
