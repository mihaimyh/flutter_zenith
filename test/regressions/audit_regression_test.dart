// Regression coverage for the September 2026 production audit.
import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zenith/zenith_identity.dart';
import 'package:flutter_zenith/core/zenith/persisted_node.dart';
import 'package:flutter_zenith/core/zenith/zenith_storage.dart';
import 'package:flutter_zenith/core/zenith/zenith_container.dart';
import 'package:flutter_zenith/core/zenith/zenith_mediator.dart';
import 'package:flutter_zenith/core/zenith/zenith_selector.dart';

class AuditCommand extends ZenithCommand<int> {
  const AuditCommand();
}

class DelayedStorage extends InMemoryStorage {
  final pending = <String, Completer<void>>{};
  @override
  Future<void> write(String key, String value) async {
    final gate = Completer<void>();
    pending[value] = gate;
    await gate.future;
    await super.write(key, value);
  }
}

void main() {
  test('F12 mediator allows parallel commands', () async {
    final container = ZenithContainer();
    final mediator = ZenithMediator(container);
    final gate = Completer<int>();
    mediator.registerCommandHandler<AuditCommand, int>((_, _) => gate.future);
    final calls = List.generate(10, (_) => mediator.send(const AuditCommand()));
    final eleventh = mediator.send(const AuditCommand());
    gate.complete(1);
    await Future.wait([...calls, eleventh]);
    container.dispose();
  });

  testWidgets('F13 selector change recomputes selection', (tester) async {
    final node = ZenithNode<List<String>>(['first', 'second']);
    Widget view(int index) => Directionality(
      textDirection: TextDirection.ltr,
      child: ZenithSelector<List<String>, String>(
        node: node,
        selector: (values) => values[index],
        builder: (_, value) => Text(value),
      ),
    );
    await tester.pumpWidget(view(0));
    await tester.pumpWidget(view(1));
    expect(find.text('first'), findsNothing);
    expect(find.text('second'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    node.dispose();
  });

  testWidgets('F1 requirements-only view denies unmet requirements', (
    tester,
  ) async {
    const policy = ZenithPolicy(
      name: 'admin',
      requirements: [RequireRole('admin')],
    );
    expect(
      const ZenithAuthorizationService()
          .evaluate(const UserSecurityContext(), policy)
          .isAuthorized,
      false,
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ZenithAuthorizeView(
          policy: policy,
          authorized: (_) => const Text('granted'),
          notAuthorized: (_, _) => const Text('denied'),
        ),
      ),
    );
    expect(find.text('denied'), findsOneWidget);
  });

  test('F2 migration completion preserves sign-out', () async {
    final c = ZenithIdentityCoordinator();
    await c.signInAnonymously(anonId: 'guest');
    final gate = Completer<void>();
    final migration = c.upgradeAnonymousAccount(
      newSession: 'user',
      onMigrate: (_, _) => gate.future,
    );
    await c.signOut();
    expect(c.state, isA<AuthUnauthenticated>());
    gate.complete();
    await migration;
    expect(c.state, isA<AuthUnauthenticated>());
    await c.signOut();
  });

  test('F3 non-string sessions require explicit identity', () async {
    final c = ZenithIdentityCoordinator();
    await expectLater(c.signIn(Object()), throwsArgumentError);
    await c.signOut();
  });

  test('F4 outbox stops old tenant after switch', () async {
    final outbox = ZenithOutboxEngine()..setActiveTenant('a');
    for (var i = 0; i < 2; i++) {
      outbox.enqueue(tenantId: 'a', action: '$i', payload: {});
    }
    final gate = Completer<void>();
    var active = 'a';
    final dispatched = <String>[];
    final flush = outbox.flush((m) async {
      dispatched.add('${m.tenantId}/$active');
      if (dispatched.length == 1) await gate.future;
    });
    active = 'b';
    outbox.setActiveTenant('b');
    gate.complete();
    await flush;
    expect(dispatched, ['a/a']);
    expect(outbox.pendingCount('a'), 1);
  });

  test('F5 concurrent flush dispatches each mutation once', () async {
    final outbox = ZenithOutboxEngine()..setActiveTenant('a');
    outbox.enqueue(tenantId: 'a', action: 'charge', payload: {});
    final gate = Completer<void>();
    var calls = 0;
    Future<void> dispatch(OutboxMutation m) async {
      calls++;
      await gate.future;
    }

    final first = outbox.flush(dispatch);
    final second = outbox.flush(dispatch);
    expect(calls, 1);
    gate.complete();
    await Future.wait([first, second]);
  });

  test('F6 failed drain still disposes removed scope', () async {
    final manager = ZenithScopeManager();
    final scope = manager.getOrCreateScope('a');
    scope.registerDrainable(
      ZenithDrainableCallback(() async {
        throw StateError('disk');
      }),
    );
    await expectLater(manager.endScopeAsync('a'), throwsStateError);
    expect(manager.hasScope('a'), false);
    expect(scope.isDisposed, true);
    scope.dispose();
  });

  test('F7 ordinary scope disposal closes pooled handle', () async {
    final manager = ZenithScopeManager();
    final scope = manager.getOrCreateScope('a');
    final pool = InMemoryDatabasePool(baseDir: '/db');
    final handle = await pool.acquireConnection('a', scope: scope);
    manager.endScope('a');
    await Future<void>.delayed(Duration.zero);
    expect(handle.isOpen, false);
    await pool.disposeAll();
  });

  test('F8 persisted writes are ordered and tolerate late writes', () async {
    final storage = DelayedStorage();
    final node = PersistedNode.string(
      key: 'x',
      defaultValue: '',
      storage: storage,
    );
    node.set('old');
    node.set('new');
    await Future<void>.delayed(Duration.zero);
    expect(storage.pending.containsKey('new'), false);
    storage.pending['old']!.complete();
    await Future<void>.delayed(Duration.zero);
    storage.pending['new']!.complete();
    await Future<void>.delayed(Duration.zero);
    expect(node.value, 'new');
    expect(storage.read('x'), 'new');
    node.dispose();
    expect(() => node.set('late'), returnsNormally);
  });

  test('F9 namespaces isolate delimiter-containing tenants', () async {
    final driver = InMemoryStorageDriver();
    final a = ZenithPartitionedStorage(driver: driver, tenantId: 'a');
    final b = ZenithPartitionedStorage(driver: driver, tenantId: 'a/b');
    await a.write('b/token', 'secret');
    expect(await b.read('token'), isNull);
  });

  test('F10 simultaneous acquire shares one handle', () async {
    final pool = InMemoryDatabasePool(baseDir: '/db');
    final handles = await Future.wait([
      pool.acquireConnection('a'),
      pool.acquireConnection('a'),
    ]);
    expect(identical(handles[0], handles[1]), true);
    await pool.disposeAll();
    expect(handles.where((h) => h.isOpen), isEmpty);
    for (final h in handles) {
      await h.close();
    }
  });

  testWidgets('F11 locked session hides authenticated content', (tester) async {
    final c = ZenithIdentityCoordinator();
    await c.signIn('a');
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ZenithAuthScope(
          coordinator: c,
          authenticatedBuilder: (_, _) => const Text('private'),
          unauthenticatedBuilder: (_) => const Text('login'),
        ),
      ),
    );
    c.lockSession();
    await tester.pump();
    expect(c.state, isA<AuthLocked>());
    expect(find.text('private'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await c.signOut();
  });
}
