import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zenith/zenith_identity.dart';

void main() {
  const service = ZenithAuthorizationService();
  const admin = UserSecurityContext(isAuthenticated: true, roles: ['admin']);

  test('empty policies deny and mixed policies require every condition', () {
    expect(
      service.evaluate(admin, const ZenithPolicy(name: 'empty')).isAuthorized,
      false,
    );
    expect(
      service
          .evaluate(
            admin,
            ZenithPolicy(
              name: 'mixed',
              requirements: const [RequireRole('admin')],
              evaluate: (_) => false,
            ),
          )
          .isAuthorized,
      false,
    );
    expect(
      service
          .evaluate(
            admin,
            ZenithPolicy(
              name: 'pending',
              requirements: const [RequireRole('admin')],
              evaluateAsync: (_) => const AsyncLoading(),
            ),
          )
          .isAuthorized,
      false,
    );
    expect(
      service
          .evaluate(
            admin,
            ZenithPolicy(
              name: 'ready',
              requirements: const [RequireRole('admin')],
              evaluateAsync: (_) => const AsyncData(true),
            ),
          )
          .isAuthorized,
      true,
    );
    expect(
      service
          .evaluate(
            admin,
            ZenithPolicy(
              name: 'throws',
              evaluate: (_) => throw StateError('bad claim'),
            ),
          )
          .isAuthorized,
      false,
    );
  });

  testWidgets('requirements react to supplied security context changes', (
    tester,
  ) async {
    Widget view(UserSecurityContext context) => Directionality(
      textDirection: TextDirection.ltr,
      child: ZenithAuthorizeView(
        securityContext: context,
        policy: const ZenithPolicy(
          name: 'admin',
          requirements: [RequireRole('admin')],
        ),
        authorized: (_) => const Text('allowed'),
        notAuthorized: (_, _) => const Text('denied'),
      ),
    );
    await tester.pumpWidget(view(const UserSecurityContext()));
    expect(find.text('denied'), findsOneWidget);
    await tester.pumpWidget(view(admin));
    expect(find.text('allowed'), findsOneWidget);
    await tester.pumpWidget(view(const UserSecurityContext()));
    expect(find.text('denied'), findsOneWidget);
  });

  testWidgets('requirements cannot be bypassed by an async grant', (
    tester,
  ) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ZenithAuthorizeView(
          policy: ZenithPolicy(
            name: 'mixed',
            requirements: const [RequireRole('admin')],
            evaluateAsync: (_) => const AsyncData(true),
          ),
          authorized: (_) => const Text('allowed'),
          notAuthorized: (_, _) => const Text('denied'),
        ),
      ),
    );
    expect(find.text('denied'), findsOneWidget);
  });

  test(
    'explicit IDs isolate object sessions and retire the old scope',
    () async {
      final c = ZenithIdentityCoordinator();
      await c.signIn(Object(), tenantId: 'a');
      final a = c.currentScope!;
      await c.signIn(Object(), tenantId: 'b');
      expect(c.currentScope!.id, 'b');
      expect(a.isDisposed, true);
      expect(c.hasScope('a'), false);
      await c.signOut();
      await expectLater(c.signIn(''), throwsArgumentError);
    },
  );

  for (final fail in [false, true]) {
    test(
      'stale migration ${fail ? 'failure' : 'success'} cannot replace a new session',
      () async {
        final c = ZenithIdentityCoordinator();
        await c.signInAnonymously(anonId: 'guest');
        final gate = Completer<void>();
        final migration = c.upgradeAnonymousAccount(
          newSession: 'target',
          onMigrate: (_, _) => gate.future,
        );
        final checked = fail
            ? expectLater(migration, throwsA(isA<ZenithMigrationException>()))
            : migration;
        await c.signIn('replacement');
        if (fail) {
          gate.completeError(StateError('network'));
        } else {
          gate.complete();
        }
        await checked;
        expect(c.currentScope!.id, 'replacement');
        expect(c.hasScope('target'), false);
        expect(c.hasScope('guest'), false);
        await c.signOut();
      },
    );
  }

  test(
    'migration validates source and same-ID target without corrupting state',
    () async {
      final c = ZenithIdentityCoordinator();
      await c.signIn('user');
      await expectLater(
        c.upgradeAnonymousAccount(
          newSession: 'other',
          onMigrate: (_, _) async {},
        ),
        throwsStateError,
      );
      await c.signOut();
      await c.signInAnonymously(anonId: 'guest');
      await expectLater(
        c.upgradeAnonymousAccount(
          newSession: 'guest',
          onMigrate: (_, _) async {},
        ),
        throwsArgumentError,
      );
      expect(c.currentScope!.isDisposed, false);
      expect(c.state, isA<AuthAnonymous>());
      await c.signOut();
    },
  );

  test(
    'migration notifies start and rollback and rejects overlapping migration',
    () async {
      final c = ZenithIdentityCoordinator();
      await c.signInAnonymously(anonId: 'guest');
      final states = <Type>[];
      c.addListener(() => states.add(c.state.runtimeType));
      final gate = Completer<void>();
      final first = c.upgradeAnonymousAccount(
        newSession: 'a',
        onMigrate: (_, _) => gate.future,
      );
      final checked = expectLater(
        first,
        throwsA(isA<ZenithMigrationException>()),
      );
      await expectLater(
        c.upgradeAnonymousAccount(newSession: 'b', onMigrate: (_, _) async {}),
        throwsStateError,
      );
      gate.completeError(StateError('failed'));
      await checked;
      expect(states, [AuthMigrating, AuthAnonymous]);
      expect(c.currentScope!.isDisposed, false);
      await c.signOut();
    },
  );

  test(
    'revocation of unrelated tenant does not sign out current tenant',
    () async {
      final c = ZenithIdentityCoordinator();
      await c.signIn('a');
      await c.ingestRemoteRevocation(
        tenantId: 'b',
        reason: RevocationReason.tokenExpired,
      );
      expect(c.currentScope!.id, 'a');
      await c.signOut();
    },
  );

  test(
    'repeated lock preserves session and anonymous lock cannot authenticate',
    () async {
      final c = ZenithIdentityCoordinator();
      await c.signInAnonymously(anonId: 'guest');
      c.lockSession();
      await c.unlockSession();
      expect(c.state, isA<AuthAnonymous>());
      await c.signIn('a');
      c.lockSession();
      c.lockSession();
      await c.unlockSession();
      expect((c.state as AuthAuthenticated).session, 'a');
      await c.signOut();
    },
  );

  testWidgets('locked builder is distinct and unlock restores private UI', (
    tester,
  ) async {
    final c = ZenithIdentityCoordinator();
    await c.signIn('a');
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ZenithAuthScope(
          coordinator: c,
          authenticatedBuilder: (_, _) => const Text('private'),
          unauthenticatedBuilder: (_) => const Text('login'),
          lockedBuilder: (_) => const Text('locked'),
        ),
      ),
    );
    c.lockSession();
    await tester.pump();
    expect(find.text('locked'), findsOneWidget);
    expect(find.text('private'), findsNothing);
    await c.unlockSession();
    await tester.pump();
    expect(find.text('private'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await c.signOut();
  });
}
