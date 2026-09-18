# Audit fixes and migration notes

The September 2026 audit regressions live in `test/regressions`. The original
13 failure cases were first run with corrected expectations and all failed.
Additional tests cover cancellation, reentrancy, errors, resource ownership and
overlapping operations.

## Identity and authorization

Object sessions require an explicit stable tenant ID:

```dart
await coordinator.signIn(session, tenantId: session.userId);
await coordinator.upgradeAnonymousAccount(
  newSession: session,
  tenantId: session.userId,
  onMigrate: migrate,
);
```

String sessions remain accepted as identity keys. Prefer an explicit user ID
when the string is a rotating token. Account changes retire the previous scope.
Migration requires an anonymous source and a distinct destination. Sign-out,
revocation and newer sign-ins invalidate pending migration results. Stale
migration errors still reach their callers without restoring the previous account.

`ZenithAuthorizeView.securityContext` defaults to anonymous. Service, route and
widget evaluation now require every supplied condition to pass. Empty, throwing,
loading and failed policies cannot grant access.

`ZenithAuthScope.lockedBuilder` supplies a separate lock screen. Without one,
the locked subtree is empty. Dormancy is an identity/UI signal; it does not freeze
direct node writes or background work. Verify biometrics before `unlockSession`.
Repeated locks preserve the original session.

## Database ownership and teardown

Production pools require an application driver factory:

```dart
final pool = ZenithDatabasePool(
  baseDir: databaseDirectory,
  openHandle: (path) => applicationDriver.open(path),
);
```

The driver must implement `ZenithDatabaseHandle`. Use `InMemoryDatabasePool`
explicitly for simulated handles. Concurrent opens share a connection. Reopening
waits for an earlier close. Cancelled acquisitions close their late results.
A handle binds to one scope at a time; await that scope's teardown before binding
a replacement. Scope and tenant IDs must match. `disposeAll` permanently ends
the pool.

`signOut` awaits resource closure. `drainAndDispose` always disposes after a
drain error, including workspace children. Repeated teardown shares the active
drain. The timeout bounds draining, not asynchronous resource closure, and does
not cancel application I/O.

`scope.dispose` invalidates the scope synchronously and starts cleanup. Await
`scope.disposalComplete` for completion or errors. `scope.onDisposeAsync` and
`ref.onDisposeAsync` register awaited cleanup. For core containers, use
`await container.disposeAsync()`, or call `dispose`/`reset` and then await
`container.disposalComplete`.

## Persistence and key encoding

`PersistedNode` orders writes across nodes sharing a backend instance and key.
Different wrapper instances are independent. `await node.flush()` observes that
node's latest accepted write and its error. `node.persistenceError` exposes the
latest failure; a subsequent successful write clears it. Flush before ending a
scope when durability matters. Disposal does not cancel accepted writes.

Partitioned storage percent-encodes tenant IDs and keys independently. Ordinary
alphanumeric IDs and keys keep their existing physical keys. Existing names
containing slashes, percent signs, spaces or other encoded characters need an
explicit data migration. Read old physical keys through the driver and write
through the new wrapper using a trusted tenant/key inventory. Do not fall back
automatically to old keys: their representation can collide between tenants.
Database path components are also encoded, including dots; existing application
paths using those characters need migration.

## Outbox and services

Call `outbox.setActiveTenant(null)` on sign-out. Every call invalidates a pending
flush, including switching away and back. Overlapping callers share one flush
completion. Enqueues during a pass wait for the next pass. If an account changes
during a pass, request another flush after the shared Future completes.

Bind dispatchers to immutable tenant-specific credentials. Changes stop later
dispatches but cannot recall a request already sent. Send `mutation.id` to a
backend supporting idempotency to protect retries after ambiguous network
failures. The queue remains in memory, without process-restart durability.
Error-observer exceptions reach the caller after queue bookkeeping completes.

`ref.registerService` returns `ZenithServiceRegistration`. Observe `started`,
`stopped` and `lastError` for lifecycle outcomes. Shutdown waits for startup, then
stops once. Failed startup triggers cleanup. Periodic tasks do not overlap;
their errors are recorded in `ZenithPeriodicService.lastError`. Shutdown waits
for an in-flight task.

`container.reset(purgeZeroize: true)` wipes current secure values. The container
no longer retains a second set of historical secure objects across resets.

## Regression coverage

- Audit failures: authorization bypass, stale migration, identity collision,
  duplicate/cross-account dispatch, failed drains, leaked connections, stale
  persistence, namespace collision, locked UI, mediator concurrency and selectors.
- Identity: mixed policies, context changes, stale success/failure, overlapping
  migration, unrelated revocation and repeated locks.
- Outbox: sign-out/return, concurrent callers, enqueue during flush, retries,
  stable IDs, observer failures and an ordered 10,000-entry batch.
- Resources: external factories, failed/late opens, closing and replacement
  scopes, async close, repeated logout/teardown, drain errors/timeouts and children.
- Persistence/core: shared keys, storage/serialization errors, same-value and
  reentrant writes, disposal, encoded namespace boundaries and real recursion.
- Services: disposal during startup, startup/shutdown errors, periodic failures
  and in-flight tasks.
