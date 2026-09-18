import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zenith/zenith_identity.dart';

class _FailingCloseHandle extends TestHandle {
  _FailingCloseHandle(super.filePath);
  @override
  Future<void> close() async => throw StateError('close failed');
}

class TestHandle implements ZenithDatabaseHandle {
  @override
  final String filePath;
  @override
  bool isOpen = true;
  int closes = 0;
  final Completer<void>? closeGate;
  TestHandle(this.filePath, {this.closeGate});
  @override
  Future<void> close() async {
    closes++;
    await closeGate?.future;
    isOpen = false;
  }
}

void main() {
  test('pool disposal reports failure to close a late acquisition', () async {
    final gate = Completer<ZenithDatabaseHandle>();
    final pool = ZenithDatabasePool(
      baseDir: '/db',
      openHandle: (_) => gate.future,
    );
    final acquisition = expectLater(
      pool.acquireConnection('a'),
      throwsStateError,
    );
    final shutdown = expectLater(pool.disposeAll(), throwsStateError);
    gate.complete(_FailingCloseHandle('/db/a'));
    await acquisition;
    await shutdown;
  });

  test('repeated logout callers both await connection shutdown', () async {
    final c = ZenithIdentityCoordinator();
    await c.signIn('a');
    final gate = Completer<void>();
    final pool = ZenithDatabasePool(
      baseDir: '/db',
      openHandle: (path) async => TestHandle(path, closeGate: gate),
    );
    await pool.acquireConnection('a', scope: c.currentScope);
    final first = c.signOut();
    var complete = false;
    final second = c.signOut().then((_) => complete = true);
    await Future<void>.delayed(Duration.zero);
    expect(complete, false);
    gate.complete();
    await Future.wait([first, second]);
    await pool.disposeAll();
  });

  test(
    'reacquire waits for release to finish closing the previous handle',
    () async {
      final gate = Completer<void>();
      var opens = 0;
      final pool = ZenithDatabasePool(
        baseDir: '/db',
        openHandle: (path) async {
          return TestHandle(path, closeGate: ++opens == 1 ? gate : null);
        },
      );
      await pool.acquireConnection('a');
      final release = pool.releaseConnection('a');
      final next = pool.acquireConnection('a');
      await Future<void>.delayed(Duration.zero);
      expect(opens, 1);
      gate.complete();
      await release;
      expect((await next).isOpen, true);
      expect(opens, 2);
      await pool.disposeAll();
    },
  );

  test('repeated manager teardown awaits the original drain', () async {
    final manager = ZenithScopeManager();
    final scope = manager.getOrCreateScope('a');
    final gate = Completer<void>();
    scope.registerDrainable(ZenithDrainableCallback(() => gate.future));
    final first = manager.endScopeAsync('a');
    var completed = false;
    final second = manager.endScopeAsync('a').then((_) => completed = true);
    await Future<void>.delayed(Duration.zero);
    expect(completed, false);
    gate.complete();
    await Future.wait([first, second]);
  });

  test(
    'a new scope cannot inherit a handle while its old owner drains',
    () async {
      final pool = InMemoryDatabasePool(baseDir: '/db');
      final oldScope = ZenithTenantScope('a');
      await pool.acquireConnection('a', scope: oldScope);
      final gate = Completer<void>();
      oldScope.registerDrainable(ZenithDrainableCallback(() => gate.future));
      final closing = oldScope.drainAndDispose();
      final fresh = ZenithTenantScope('a');
      await expectLater(
        pool.acquireConnection('a', scope: fresh),
        throwsStateError,
      );
      gate.complete();
      await closing;
      expect((await pool.acquireConnection('a', scope: fresh)).isOpen, true);
      await fresh.drainAndDispose();
      await pool.disposeAll();
    },
  );

  test(
    'external factory opens exactly once for concurrent acquisitions',
    () async {
      final gate = Completer<ZenithDatabaseHandle>();
      var opens = 0;
      final pool = ZenithDatabasePool(
        baseDir: '/db',
        openHandle: (path) {
          opens++;
          return gate.future;
        },
      );
      final first = pool.acquireConnection('a');
      final second = pool.acquireConnection('a');
      final handle = TestHandle('/db/a');
      gate.complete(handle);
      expect(await first, same(handle));
      expect(await second, same(handle));
      expect(opens, 1);
      await pool.disposeAll();
      expect(handle.closes, 1);
    },
  );

  test('failed acquire can retry', () async {
    var attempts = 0;
    final pool = ZenithDatabasePool(
      baseDir: '/db',
      openHandle: (path) async {
        if (++attempts == 1) throw StateError('disk');
        return TestHandle(path);
      },
    );
    await expectLater(pool.acquireConnection('a'), throwsStateError);
    expect((await pool.acquireConnection('a')).isOpen, true);
    await pool.disposeAll();
  });

  for (final disposePool in [false, true]) {
    test(
      'late acquisition closes after ${disposePool ? 'pool' : 'scope'} disposal',
      () async {
        final gate = Completer<ZenithDatabaseHandle>();
        final scope = ZenithTenantScope('a');
        final pool = ZenithDatabasePool(
          baseDir: '/db',
          openHandle: (_) => gate.future,
        );
        final checked = expectLater(
          pool.acquireConnection('a', scope: scope),
          throwsStateError,
        );
        final shutdown = disposePool ? pool.disposeAll() : Future<void>.value();
        if (!disposePool) scope.dispose();
        final handle = TestHandle('/db/a');
        gate.complete(handle);
        await checked;
        await shutdown;
        expect(handle.isOpen, false);
        expect(handle.closes, 1);
        await pool.disposeAll();
      },
    );
  }

  test('old scope cleanup cannot close a replacement handle', () async {
    final pool = ZenithDatabasePool(
      baseDir: '/db',
      openHandle: (path) async => TestHandle(path),
    );
    final oldScope = ZenithTenantScope('a');
    await pool.acquireConnection('a', scope: oldScope);
    await pool.releaseConnection('a');
    final replacement = await pool.acquireConnection('a');
    oldScope.dispose();
    await oldScope.disposalComplete;
    expect(replacement.isOpen, true);
    await pool.disposeAll();
  });

  test('scope mismatch and closed scope reject before opening', () async {
    var opens = 0;
    final pool = ZenithDatabasePool(
      baseDir: '/db',
      openHandle: (path) async {
        opens++;
        return TestHandle(path);
      },
    );
    await expectLater(
      pool.acquireConnection('a', scope: ZenithTenantScope('b')),
      throwsArgumentError,
    );
    final dead = ZenithTenantScope('a')..dispose();
    await expectLater(
      pool.acquireConnection('a', scope: dead),
      throwsStateError,
    );
    expect(opens, 0);
    await pool.disposeAll();
  });

  test(
    'logout awaits asynchronous close and repeated binds close only once',
    () async {
      final gate = Completer<void>();
      final c = ZenithIdentityCoordinator();
      await c.signIn('a');
      final handle = TestHandle('/db/a', closeGate: gate);
      final pool = ZenithDatabasePool(
        baseDir: '/db',
        openHandle: (_) async => handle,
      );
      await pool.acquireConnection('a', scope: c.currentScope);
      await pool.acquireConnection('a', scope: c.currentScope);
      var finished = false;
      final logout = c.signOut().then((_) => finished = true);
      await Future<void>.delayed(Duration.zero);
      expect(finished, false);
      expect(c.state, isA<AuthUnauthenticated>());
      gate.complete();
      await logout;
      expect(handle.closes, 1);
      await pool.disposeAll();
    },
  );

  test('sync drain errors still run other drains and dispose', () async {
    final scope = ZenithTenantScope('a');
    var otherDrained = false;
    scope.registerDrainable(
      ZenithDrainableCallback(() => throw StateError('sync')),
    );
    scope.registerDrainable(
      ZenithDrainableCallback(() async {
        otherDrained = true;
      }),
    );
    await expectLater(scope.drainAndDispose(), throwsStateError);
    expect(otherDrained, true);
    expect(scope.isDisposed, true);
  });

  test(
    'concurrent teardown shares drains, blocks new work and bounds timeout',
    () async {
      final scope = ZenithTenantScope('a');
      final gate = Completer<void>();
      var drains = 0;
      var ran = false;
      scope.registerDrainable(
        ZenithDrainableCallback(() {
          drains++;
          return gate.future;
        }),
      );
      final first = scope.drainAndDispose(
        timeout: const Duration(milliseconds: 5),
      );
      final second = scope.drainAndDispose();
      scope.runWithToken((_) async {
        ran = true;
      });
      await Future.wait([first, second]);
      expect(drains, 1);
      expect(ran, false);
      expect(scope.isDisposed, true);
      gate.completeError(StateError('late error is observed'));
      await Future<void>.delayed(Duration.zero);
    },
  );

  test('user teardown drains workspace children', () async {
    final user = ZenithUserScope('a');
    final workspace = user.getOrCreateWorkspaceScope('project');
    var drained = false;
    workspace.registerDrainable(
      ZenithDrainableCallback(() async {
        drained = true;
      }),
    );
    await user.drainAndDispose();
    expect(drained, true);
    expect(workspace.isDisposed, true);
    expect(() => user.getOrCreateWorkspaceScope('late'), throwsStateError);
  });
}
