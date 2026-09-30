---
name: flutter-zenith-identity
description: Multi-tenant scoping, identity lifecycle, authorization, tenant storage, offline outbox, tenant databases, cancellation and secure buffers in flutter_zenith's identity library. Use when importing package:flutter_zenith/zenith_identity.dart, managing app/user/workspace scopes, sign-in/sign-out/anonymous upgrades, policy-based authorization, ZenithAuthorizeView, tenant-partitioned storage, ZenithOutboxEngine, ZenithDatabasePool, or ZenithCancellationToken.
license: MIT
---

# flutter_zenith — identity, scopes, and authorization

Read the parent `flutter-zenith` skill first. Import the identity library separately and prefix it when also importing core, because it declares its own `AuthUnauthenticated`/`AuthAuthenticated` and a different `BuildContext.zenith`:

```dart
import 'package:flutter_zenith/flutter_zenith.dart';
import 'package:flutter_zenith/zenith_identity.dart' as identity;
```

It re-exports core `ZenithKey`, `ZenithNode`, and `AsyncValue`, so you rarely need both imports for basic work.

## Scope model

Three-tier hierarchy, three lifetimes:

```
ZenithTenantScope('__app__')          // app scope — never a scoped container
  └─ ZenithUserScope(userId)          // account: identity, profile, credentials
       └─ ZenithTenantScope(workspaceId)  // workspace: tenant DB, outbox, project nodes
```

```dart
final manager = identity.ZenithScopeManager();

final userScope = manager.getOrCreateUserScope('user_123');
final workspace = userScope.getOrCreateWorkspaceScope('ws_42');

userScope.register(identity.ZenithKey<Cart>('cart'), () => Cart());      // scoped lifetime (default)
userScope.register(identity.ZenithKey<ApiClient>('api'), () => ApiClient(),
    lifetime: identity.ZenithLifetime.singleton);
userScope.resolve(identity.ZenithKey<Cart>('cart'));

await manager.endScopeAsync('user_123');            // drain then dispose
manager.endScope('user_123');                        // immediate dispose
userScope.endWorkspaceScope('ws_42');                // keep the user signed in
```

- The **captive dependency guard** throws when a `singleton`-tagged registration resolves a `scoped` key from a scoped container. The hierarchy defines lifetimes — it does **not** automatically inherit app→tenant dependencies.
- `endScopeAsync`/`drainAndDispose` await registered `ZenithDrainable`s (bounded by a timeout), then dispose. The timeout does not cancel arbitrary I/O.
- `scope.dispose()` is synchronous and starts cleanup; await `scope.disposalComplete` for completion/errors. `scope.onDisposeAsync` registers awaited cleanup.
- Dormancy (`markDormant`/`isDormant`) is an identity/UI signal, not a write lock.
- `ZenithScopeManager.bootstrapHeadless(tenantId: …)` creates a scope for background work without widget bindings (still requires Flutter, not a Dart CLI).

## Draining

```dart
class DraftFlusher extends identity.ZenithDrainable {
  @override Future<void> drain() => saveDraft();
}
scope.registerDrainable(DraftFlusher());
// or: scope.registerDrainable(identity.ZenithDrainableCallback(() => saveDraft()));
```

## Identity lifecycle

```dart
final coordinator = identity.ZenithIdentityCoordinator();

await coordinator.signIn(session);                       // string session can be the id
await coordinator.signIn(session, tenantId: session.userId); // objects REQUIRE a stable tenantId
await coordinator.signInAnonymously(anonId: 'anon_123');

await coordinator.upgradeAnonymousAccount(
  newSession: 'session-token',
  tenantId: 'user_456',
  onMigrate: (fromContainer, toContainer) async {
    // Copy application-owned data into the new scope.
  },
);

await coordinator.signOut();                             // awaits resource teardown
coordinator.state;         // identity.ZenithAuthState
coordinator.currentScope;  // identity.ZenithTenantScope?
coordinator.addListener(() {}); / removeListener(...)
```

Auth states: `AuthUnauthenticated`, `AuthAnonymous(anonId)`, `AuthAuthenticated<T>(session)`, `AuthMigrating(fromId, toId)`, `AuthLocked<T>(session)`.

- Object sessions need an explicit stable `tenantId`; string tokens should also pass a stable id so rotation doesn't change identity.
- Migration requires an anonymous source and a distinct, unused destination. On failure the anonymous scope is restored and a `ZenithMigrationException` is thrown. Superseded migrations can't overwrite a newer sign-in/out; stale migration errors still reach their callers.
- `onMigrate` gets both containers concurrently: read `fromContainer`, write `toContainer`. Application storage writes still need their own transactional strategy.

## Lock and revocation

```dart
coordinator.lockSession();          // scope goes dormant; state → AuthLocked
await coordinator.unlockSession();  // verify biometrics in YOUR app before calling this

coordinator.onSecurityRevocation((reason) { /* RevocationReason */ });
await coordinator.ingestRemoteRevocation(tenantId: 'user_123', reason: identity.RevocationReason.tokenExpired);
```

`lockSession` is a UI/identity signal — direct node writes and background work still run. `ingestRemoteRevocation` consumes an app-supplied event; it does not open a server connection.

## Tenant storage

```dart
final driver = identity.InMemoryStorageDriver(); // implement StorageDriver for real backends
final a = identity.ZenithPartitionedStorage(driver: driver, tenantId: 'user_a');
final b = identity.ZenithPartitionedStorage(driver: driver, tenantId: 'user_b');

await a.write('token', 'abc');
await b.read('token'); // null — isolated
```

Keys are namespaced `tenants/{encodedTenantId}/{encodedKey}`; tenant ids and keys are percent-encoded independently. This is fully async and separate from core `ZenithStorage`.

## Outbox

```dart
final outbox = identity.ZenithOutboxEngine()..setActiveTenant('user_a');
outbox.enqueue(tenantId: 'user_a', action: 'saveDraft', payload: {'title': 'Travel'});

await outbox.flush((mutation) async => api.send(mutation, idempotencyKey: mutation.id));
outbox.pendingCount('user_a');
outbox.deadLetterQueue;

outbox.setActiveTenant(null); // on sign-out
```

- Only mutations for the **active tenant** dispatch; inactive tenants' work stays queued (prevents cross-account dispatch).
- Individual failures increment `retryCount`, set exponential backoff `nextRetryAfter` (capped), and move to the dead-letter queue at `maxRetries`. Failures don't abort the whole pass (no head-of-line blocking).
- Concurrent `flush` callers share one completion; enqueues during a pass wait for the next pass. Every `setActiveTenant` invalidates pending work, including switching away and back.
- In-memory only — persist elsewhere if mutations must survive restarts. Bind dispatchers to immutable tenant credentials; a sign-out cannot recall an in-flight request.

## Authorization

```dart
const policy = identity.ZenithPolicy(
  name: 'edit',
  requirements: [identity.RequireAuthenticatedUser(), identity.RequireRole('editor')],
);

const security = identity.UserSecurityContext(isAuthenticated: true, roles: ['editor']);
final decision = const identity.ZenithAuthorizationService().evaluate(security, policy);
decision.isAuthorized;

// Reactive policy (watches nodes in the view):
final exportPolicy = identity.ZenithPolicy(
  name: 'export4k',
  evaluate: (ref) => ref.watch(entitlementNode).contains('export_4k'),
);
```

Built-in requirements: `RequireAuthenticatedUser`, `RequireEntitlement(str)`, `RequireRole(str)`, `RequireMaxMonthlyBandwidth(quotaGb)`. Every supplied condition must pass. Empty, throwing, failed and pending policies deny access (fail-closed). Async policies return `AsyncValue<bool>`; loading/error never grant.

Route guard:

```dart
final redirect = identity.ZenithRouteGuard.evaluate(
  context: security, policy: policy,
  authService: const identity.ZenithAuthorizationService(),
  deniedRedirectPath: '/login',
); // null when allowed
```

Conditional UI:

```dart
identity.ZenithAuthorizeView(
  policy: exportPolicy,
  authorized: (ctx) => const ExportButton(),
  notAuthorized: (ctx, result) => const PaywallTrigger(), // result.reason may explain
  authorizing: (ctx) => const Shimmer(),                  // async policies only
);
identity.ZenithAuthorizeView.hidden(policy: p, authorized: (ctx) => const Secret());
identity.ZenithAuthorizeView.locked(policy: p, authorized: (ctx) => const Secret());
```

## Scope widgets

```dart
identity.ZenithScopeProvider(scope: tenantScope, child: child); // does NOT own disposal
final scope = identity.ZenithScopeProvider.of(context);
context.zenithScope;                     // same, via extension
context.zenith(someKey);                 // resolve a key from the nearest tenant scope

identity.ZenithAuthScope(
  coordinator: coordinator,
  authenticatedBuilder: (ctx, scope) => HomeScreen(scope: scope),
  unauthenticatedBuilder: (ctx) => LoginScreen(),
  lockedBuilder: (ctx) => const LockScreen(), // defaults to empty
);

context.zenithShowModalBottomSheet(builder: (sheetCtx) => Text(sheetCtx.zenith(aliasKey)));
```

`ZenithAuthScope` unwinds the navigation stack before disposing the scope container, and keys the authenticated subtree by scope object — replacing an account discards that subtree's local widget state. Keep deliberately shared state above that boundary. Use `zenithShowModalBottomSheet` to tunnelling the scope across a modal route.

## Cancellation

```dart
scope.runWithToken((token) async {
  token.onCancel(() => httpClient.close()); // abort physical I/O
  final data = await httpClient.get('/api/data');
  if (token.isCancelled) return;
  node.value = data;
});

scope.runGuarded(() async { /* cancelled when scope disposes */ });

final runner = identity.ZenithConcurrencyRunner();
runner.runAsyncRestartable((token) async { token.onCancel(() => req.abort()); await req.send(); });
runner.cancelCurrent();
```

`runGuarded`/`runWithToken` return void and deliver task failures to the zone. The standalone restartable runner also returns void and consumes task failures — handle/report errors inside its task.

## Tenant database pool

```dart
final pool = identity.ZenithDatabasePool(
  baseDir: databaseDirectory,
  openHandle: (path) => myDriver.open(path), // returns a ZenithDatabaseHandle
);

final handle = await pool.acquireConnection('user_123', scope: userScope);
pool.bindScope(userScope);                 // binds once; released on scope teardown
await pool.releaseConnection('user_123');  // or await scope teardown
await pool.disposeAll();                   // permanently closes the pool
```

The pool generates encoded tenant paths (`{baseDir}/tenants/{encoded}/data.db`), shares concurrent opens, and validates scope/tenant id matches. It bundles no SQLite driver — supply one. A handle binds to one scope at a time; await the prior scope's teardown before rebinding. `InMemoryDatabasePool` is for tests only.

## Secure buffers

```dart
final token = identity.ZenithSecureBytes(Uint8List.fromList(bytes)); // wraps the buffer directly
scope.container.getOrCreate(nodeKey, (_) => token);
manager.endScope('user_123', purgeZeroize: true); // zeroes the original buffer
token.isZeroized;
```

`ZenithSecureBytes` implements `Zeroizable`. Zeroization overwrites the caller's buffer; it does not erase copies, immutable strings or OS storage, and does not encrypt. Normal sign-out does not purge automatically — pass `purgeZeroize: true`.

## Inter-isolate invalidation

```dart
scope.listenToInterIsolateInvalidations('zenith.port', onInvalidate: (nodeKey) => …);
// Background isolate: send identity.ZenithInvalidateMessage(tenantId: 'user_123', nodeKey: 'cart')
// through IsolateNameServer.sendPortForName(...). Messages are tenant-filtered.
```

## Recipes

**App shell** — one `ZenithScopeManager`, a `ZenithIdentityCoordinator`, and a `ZenithAuthScope` at the root; hand the authenticated `ZenithTenantScope.container` to a `ZenithScope`.

**Sign-out flow** — `outbox.setActiveTenant(null)` → `await coordinator.signOut()` → optionally purge secure nodes.

**Feature gating** — reactive `ZenithPolicy.evaluate` with `ref.watch(featureNode)` inside `ZenithAuthorizeView`.

## Gotchas

1. `ZenithScopeProvider` resolves non-listening and does **not** dispose the scope; rebuild consumers when replacing it.
2. `signOut` awaits closure; `dispose()` alone does not — await `disposalComplete`.
3. Never resolve a scoped key from a singleton registration in a scoped container (throws).
4. The outbox is in-memory and tenant-filtered; a tenant switch stops later dispatches but cannot recall an in-flight request.
5. Authorization is fail-closed; UI checks complement server-side authorization, they don't replace it.
6. The DB pool bundles no driver; await the old scope's teardown before rebinding a handle.
7. `ZenithSecureBytes` wraps (not copies) the buffer; copies are not zeroized.

## Reference

- [reference/api-reference.md](reference/api-reference.md) — exact signatures for every identity API.
