# flutter_zenith

[![pub package](https://img.shields.io/pub/v/flutter_zenith.svg)](https://pub.dev/packages/flutter_zenith)
[![CI](https://github.com/mihaimyh/flutter_zenith/actions/workflows/ci.yml/badge.svg)](https://github.com/mihaimyh/flutter_zenith/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Container-scoped state management and dependency injection for Flutter. Widgets subscribe to the nodes they read; containers own dependencies and their cleanup. Optional identity APIs add tenant scopes, account transitions, authorization, storage namespaces and an in-memory outbox.

The package has no runtime dependencies beyond the Flutter SDK and requires no code generation. It requires Dart **3.12.2 or later within Dart 3**, provided by a compatible Flutter SDK. It is a Flutter package, not a standalone Dart server/CLI library. Isolate and IPC features require a platform that supports their underlying Flutter/Dart APIs.

## Install

```sh
flutter pub add flutter_zenith
```

Or add the dependency explicitly:

```yaml
dependencies:
  flutter_zenith: ^0.13.0
```

Use the core entry point for nodes, containers, widgets and application utilities:

```dart
import 'package:flutter_zenith/flutter_zenith.dart';
```

Use a prefix for identity APIs when importing both libraries. They contain distinct auth state types and different `BuildContext.zenith` extensions:

```dart
import 'package:flutter_zenith/zenith_identity.dart' as identity;
```

See [API reference](https://pub.dev/documentation/flutter_zenith/latest/), the [expense form example](example/lib/expense_draft/expense_draft_form.dart), [changelog](CHANGELOG.md) and [migration notes](doc/audit-fixes.md).

## Quick start

This complete app creates a typed counter in a container. `ZenithBuilder` tracks the node read inside its builder and rebuilds when that value changes. `ZenithScope` owns the container and disposes it when removed.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_zenith/flutter_zenith.dart';

const counterKey = ZenithKey<int>('counter');

void main() {
  final container = ZenithContainer();
  runApp(
    ZenithScope(
      container: container,
      child: const MaterialApp(home: CounterScreen()),
    ),
  );
}

class CounterScreen extends StatelessWidget {
  const CounterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final counter = context.container.getOrCreate(counterKey, (_) => 0);
    return Scaffold(
      body: Center(
        child: ZenithBuilder(builder: (_) => Text('${counter.value}')),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => counter.value++,
        child: const Icon(Icons.add),
      ),
    );
  }
}
```

Create containers outside `build`. A `ZenithScope` also disposes the old container when replaced with a different one. Do not place the same owned container in several independent `ZenithScope` widgets.

## Feature catalog

### Core library

| Capability | Public APIs | Contract |
| --- | --- | --- |
| Reactive values | `ZenithNode`, `ZenithSubscriber`, `ZenithSubscription` | Synchronous notifications, equality-based write suppression, cancellation handles and weak subscriber references. |
| Derived state | `ComputedNode` | Tracks synchronous source reads, reconciles changing dependencies and rejects direct writes. |
| Dependency injection | `ZenithContainer`, `ZenithRef`, `ZenithKey`, `ZenithOverride` | Typed factories, cached nodes, scoped cleanup and explicit parent lookup. |
| Parameterized dependencies | `ZenithFamily`, `ZenithFamilyRegistry` | Argument-based keys, tracked family invalidation and key registry cleanup. |
| Environment configuration | `ZenithEnvironment`, `environmentOverrides` | Select development, staging or production overrides when constructing a container. |
| Reactive widgets | `ZenithScope`, `ZenithBuilder`, `ZenithConsumer`, `ZenithConsumerWidget` | Container access and dependency-driven builds, with an optional builder error UI. |
| Stateful integration | `ZenithStatefulWidget`, `ZenithState`, `ZenithStateMixin`, `ZenithController` | Widget/controller lifecycle integration and imperative listeners. |
| Selection and effects | `ZenithSelector`, `ZenithListener`, `watch`, `select`, `watchNode`, `selectNode` | Selected-value rebuild filtering through `ZenithSelector`; side effects through listeners. |
| Safe scheduling | `ZenithSafeRebuild` | Defers and coalesces rebuild work requested during Flutter build/layout phases. |
| Async state | `AsyncValue`, `AsyncData`, `AsyncLoading`, `AsyncError` | Exhaustive matching, previous loading data, equality and convenience getters. |
| Async operations | `runAsync`, node `guard`, `ZenithMutation` | Mounted-safe writes; mutations reject stale results and rethrow current failures. |
| Concurrency | `runAsyncGuarded`, `ConcurrencyStrategy`, `runInIsolate` | Concurrent, droppable or restartable results; explicit isolate offload. |
| Scope generations | `ZenithScopeGuard`, `ZenithScopeToken` | Capture and invalidate tokens for application work across scope changes. |
| Streams | `watchStream`, node `watch` | Stream data/errors become async state; cancellation joins asynchronous cleanup. |
| Persistence | `PersistedNode`, `ZenithStorage`, `InMemoryStorage` | Synchronous hydration, ordered async writes, `flush` and `persistenceError`. |
| Middleware | `ZenithMiddleware` | Transform or cancel writes and observe accepted writes. |
| Core auth models | `AuthState` and its variants | Data model for unauthenticated, authenticating, authenticated and error states. |
| Configuration | `ZenithConfigNode` | Decode map payloads into typed configuration. |
| Feature flags | `ZenithFeature`, `FeatureNode`, `ZenithFeatureBuilder` | Boolean state and deterministic percentage rollout by user/feature. |
| Validation | `ZenithValidator`, `PropertyRuleBuilder`, `ZenithValidatedNode` | Fluent rules, custom predicates and per-field validation results. |
| Messaging | `ZenithMediator`, commands, events, pipeline behaviors | One command handler, sequential event handlers and zone-local recursion checks. |
| Resilience | `ZenithResiliencePipeline`, `runResilient` | Retry/backoff/jitter, circuit breaking and a monotonic sliding-window limiter. |
| Background services | `ZenithService`, `ZenithPeriodicService`, `ZenithIsolateService` | Observable start/stop, non-overlapping periodic tasks and scoped isolate lifetime. |
| Logging | `ZenithLogger`, `ZenithLogSink`, `ConsoleSink`, `MemoryRingBufferSink` | Structured events, top-level sensitive-property redaction and bounded in-memory logs. |
| Diagnostics | `ZenithObserver`, `ZenithLogObserver`, `Zenith.onDebugPrint` | Mutation observation and opt-in debug output. Lifecycle observer methods are declared but not currently dispatched. |
| Sensitive values | `Zeroizable` | Opt-in overwriting of a value's mutable buffer during replacement or explicit purge. |
| Testing | `ZenithTestContainerBuilder` | Build containers with typed dependency overrides. |

### Identity library

| Capability | Public APIs | Contract |
| --- | --- | --- |
| Scope ownership | `ZenithScopeManager`, `ZenithTenantScope`, `ZenithUserScope`, `ZenithLifetime` | App, user and workspace lifetimes; singleton-construction checks for scoped dependencies. |
| Draining | `ZenithDrainable`, `ZenithDrainableCallback`, `drainAndDispose` | Drain before disposal, then await registered asynchronous cleanup. |
| Identity transitions | `ZenithIdentityCoordinator`, `ZenithAuthState`, `ZenithMigrationException` | Anonymous sessions, account upgrades, sign-in/out and stale-migration protection. |
| Lock and revocation | `AuthLocked`, `lockSession`, `unlockSession`, `RevocationReason` | Lock-screen state and application-supplied remote revocation events. |
| Tenant storage | `StorageDriver`, `InMemoryStorageDriver`, `ZenithPartitionedStorage` | Asynchronous storage with independently encoded tenant/key namespaces. |
| Outbox | `ZenithOutboxEngine`, `OutboxMutation` | In-memory tenant-filtered dispatch, stable IDs, retry/backoff and dead letters. |
| Policies | `ZenithPolicy`, `PolicyRef`, `ZenithRequirement`, `UserSecurityContext` | Custom predicates plus authentication, entitlement, role and bandwidth requirements. |
| Authorization | `ZenithAuthorizationService`, `AuthorizationResult`, `ZenithRouteGuard` | Fail-closed policy evaluation and redirect decisions. |
| Conditional UI | `ZenithAuthorizeView`, `.hidden`, `.locked` | Authorized, denied and pending views; reactive reads through `PolicyRef.watch`. |
| Scope widgets | `ZenithScopeProvider`, `ZenithAuthScope` | Scope access and account-specific subtree replacement. The provider does not own disposal. |
| Modal bridge | `zenithShowModalBottomSheet` | Forward the current scope into a modal route. |
| Cancellation | `ZenithCancellationToken`, `ZenithConcurrencyRunner`, `runWithToken` | Cooperative task cancellation with callbacks for physical I/O abort. |
| Database ownership | `ZenithDatabasePool`, `ZenithDatabaseHandle`, `InMemoryDatabasePool` | Driver-supplied tenant handles, shared concurrent acquisition and awaited release. |
| Secure buffers | `ZenithSecureBytes` | Overwrite a caller-supplied byte buffer; no encryption or protection of copied values. |
| Inter-isolate invalidation | `ZenithInvalidateMessage`, `listenToInterIsolateInvalidations` | Tenant-filtered invalidation through Flutter's `IsolateNameServer`. |
| Background bootstrap | `ZenithScopeManager.bootstrapHeadless` | Create a scope for Flutter background work without building widgets. It does not make the package Dart-CLI compatible. |

## Nodes, selection and ownership

Read `.value` inside a `ZenithBuilder` or consumer build to subscribe automatically. Dependency collection is synchronous; reads after an `await` are not part of the build. Keep computed callbacks synchronous and free of writes to their own dependencies.

```dart
final count = ZenithNode(1);
final doubled = ComputedNode(() => count.value * 2);
count.value = 3;
assert(doubled.value == 6);
doubled.dispose();
count.dispose();
```

Setting an equal value does not notify. Use `invalidate()` for an explicit notification, including when an equal `AsyncData` must trigger an effect. Middleware returns `null` to cancel a write, so nullable values need that cancellation contract considered explicitly.

`ZenithSelector` compares the selected result before rebuilding. `context.select` computes a selection inside normal read tracking; it does not provide that separate comparison boundary. Use `ZenithListener` for navigation and other side effects rather than doing them in a builder.

Manual subscribers must be retained by their owner because node references to them are weak. Keep and call the returned cancellation handle when finished. Nodes created directly, including computed and persisted nodes, need explicit ownership/cleanup; disposing a container does not recursively dispose arbitrary objects stored inside a node.

## Typed dependencies and families

Factories receive a `ZenithRef` for cleanup and guarded updates:

```dart
const nameKey = ZenithKey<String>('displayName');
final container = ZenithContainer(
  overrides: [ZenithOverride(nameKey, (_) => 'Test account')],
);
final name = container.getOrCreate(nameKey, (_) => 'Guest');
assert(name.value == 'Test account');
```

`getOrCreate` caches locally. `maybeReadKey` explicitly searches the parent chain; local registration/resolution does not automatically inherit every parent dependency. Environment-specific overrides take precedence over general overrides.

```dart
const profile = ZenithFamily<String, String>('profile');
final alice = container.getOrCreate(profile('alice'), (_) => 'Alice');
final registry = profile.registry();
registry.key('alice');
registry.invalidateAll(container);
registry.forgetAll();
```

As of 0.13.0, family identity includes the value type, argument type, family name and the argument's equality/hash. Arguments must have stable equality while used as keys. Always call `family(argument)` instead of reconstructing `ZenithKey('family#argument')`. Forgetting registry entries stops tracking keys; it does not remove container-owned nodes.

## Async work and cleanup

```dart
final container = ZenithContainer();
final ref = ZenithRef(container);
final result = ZenithNode<AsyncValue<String>>(const AsyncData('initial'));

await ref.runAsyncGuarded(
  result,
  () async => 'loaded',
  strategy: ConcurrencyStrategy.restartable,
);

await container.disposeAsync();
result.dispose();
```

`runAsync` records errors as `AsyncError` and guards writes by ref lifetime. `runAsyncGuarded` adds result ordering: concurrent accepts each completion, droppable skips a task while loading, restartable ignores superseded completions. Ignoring a completion does not cancel its underlying I/O. `ZenithMutation` adds pending state and rethrows the current operation's failure to its caller.

Register synchronous cleanup with `ref.onDispose` and asynchronous cleanup with `ref.onDisposeAsync`. Failed factories release registered resources before rethrowing. `watchStream` registers awaited cancellation automatically. `dispose()` invalidates ownership synchronously; await `disposalComplete` or use `disposeAsync()` to observe async cleanup. `reset()` awaits cleanup while keeping the container reusable.

For hosted services, `ref.registerService(service)` returns `started`, `stopped`, `lastError` and an idempotent `stop()`. Periodic services do not overlap tasks and wait for an active task during shutdown. Isolate services need a platform with isolate support.

## Persistence and outbox

```dart
final storage = InMemoryStorage();
final theme = PersistedNode.string(
  key: 'theme',
  defaultValue: 'system',
  storage: storage,
);
theme.value = 'dark';
await theme.flush();
theme.dispose();
```

Supply a `ZenithStorage` implementation for real persistence. Its read method is synchronous, so asynchronous backends need preloading/caching or a separate hydration flow. Accepted writes are serialized across nodes sharing the same backend object and key. `flush()` observes the node's latest accepted write; `persistenceError` exposes its failure. Disposal does not cancel accepted writes.

Identity `StorageDriver` is a separate, fully asynchronous interface. `ZenithPartitionedStorage` is not directly interchangeable with `ZenithStorage`.

```dart
final outbox = identity.ZenithOutboxEngine()..setActiveTenant('alice');
outbox.enqueue(
  tenantId: 'alice',
  action: 'saveDraft',
  payload: {'title': 'Travel'},
);
// Supply a dispatcher bound to Alice's credentials:
// await outbox.flush((mutation) => api.send(mutation));
outbox.setActiveTenant(null);
```

The outbox is in-memory and is not a durable transaction log. Persist it outside this component if mutations must survive process restarts. Activate/deactivate it explicitly on identity transitions. A tenant change stops later dispatches but cannot recall an in-flight request. Pass `mutation.id` to a backend with idempotency support when retrying ambiguous failures. Concurrent flush callers share a completion; newly enqueued work waits for the next pass. Inactive tenants' work remains queued.

## Identity, scopes and authorization

```dart
final coordinator = identity.ZenithIdentityCoordinator();
await coordinator.signInAnonymously(anonId: 'guest-123');
await coordinator.upgradeAnonymousAccount(
  newSession: 'session-token',
  tenantId: 'user-456',
  onMigrate: (from, to) async {
    // Copy application-owned data into the new scope.
  },
);
await coordinator.signOut();
```

Object sessions require an explicit stable `tenantId`. For string tokens, also provide a stable ID so token rotation does not change account identity. Migration requires a distinct unused destination. A failed current migration restores anonymous identity; application storage writes still need their own transactional strategy. Superseded migrations cannot overwrite a newer sign-in or logout.

Use `ZenithAuthScope` for authenticated, unauthenticated and locked builders. Account scope replacement resets the authenticated subtree, including local widget State. `ZenithScopeProvider` exposes an existing scope but does not dispose it. Its lookup is non-listening and can be used in lifecycle callbacks; rebuild consumers when replacing a provider manually. The modal bridge forwards a scope without assuming that the modal route shares its original inherited context.

User scopes own workspace scopes. This hierarchy defines lifetimes, not automatic app-to-tenant dependency inheritance. A singleton registration tag checks for captive scoped dependencies; it does not move the instance to `appScope`.

`lockSession` is a UI/identity signal. Direct node writes and background work remain allowed. Perform biometric verification in your application before calling `unlockSession`. `ingestRemoteRevocation` consumes an application-supplied revocation event; it does not open a server connection.

```dart
const policy = identity.ZenithPolicy(
  name: 'edit',
  requirements: [
    identity.RequireAuthenticatedUser(),
    identity.RequireRole('editor'),
  ],
);
const security = identity.UserSecurityContext(
  isAuthenticated: true,
  roles: ['editor'],
);
final decision = const identity.ZenithAuthorizationService()
    .evaluate(security, policy);
assert(decision.isAuthorized);
```

Every supplied condition must pass. Empty, throwing, failed and pending policies deny access. An async policy returns an `AsyncValue<bool>` snapshot; a reactive view watches its nodes through `PolicyRef.watch`. UI checks complement server-side authorization; the application supplies trusted security context.

## Resource isolation and cancellation

`ZenithDatabasePool` accepts `baseDir` and an `openHandle` factory implementing `ZenithDatabaseHandle`. It generates encoded tenant paths, shares concurrent opens and can bind a handle to a matching scope. It does not bundle a SQLite driver. Await the old scope's teardown before rebinding its connection to a replacement. `disposeAll` permanently closes the pool.

Register `ZenithDrainable` objects to flush before scope disposal. The drain timeout bounds draining, not subsequent asynchronous resource closure, and does not cancel arbitrary I/O. `runWithToken` supplies a token whose `onCancel` callbacks can abort application requests. `runGuarded` and `runWithToken` return void and deliver task failures to the zone. The standalone restartable runner also returns void and currently consumes task failures; handle/report errors inside its task when needed.

`ZenithSecureBytes` wraps the original mutable buffer. Replacing a zeroizable node value wipes the old value; explicit `purgeZeroize: true` wipes current values during reset/disposal. This does not erase copies, immutable strings or OS storage, and does not encrypt data. Normal identity sign-out does not request a secure purge automatically.

## Application utilities

- `ZenithConfigNode.updateRaw` decodes a map into typed settings. Supply the decoder.
- `ZenithFeature.percentageRollout` deterministically assigns a user/feature pair to a percentage bucket. `FeatureNode` and `ZenithFeatureBuilder` bind flags to UI.
- `ZenithValidator` supports non-empty, email, length, numeric and custom predicate rules. Validate domain-specific formats with `must` when the built-in rules do not fit.
- `ZenithMediator.send` dispatches typed commands through registered behaviors; `publish` visits event handlers sequentially. Event failures are debug-logged and do not stop other handlers. Command recursion depth is scoped to each async call chain.
- `ZenithResiliencePipeline` composes retry, circuit breaking and rate limiting. Rate limiting counts admitted executions, while retries happen inside one execution. Its timestamp queue uses monotonic elapsed time.
- `ZenithLogger` emits structured events to custom sinks. Redaction covers recognized top-level property names, including `auth_header`; it is not recursive sanitization of arbitrary message text or exception objects.
- `Zenith.observer` observes mutations. `Zenith.onDebugPrint` supplies opt-in debug output. Other declared lifecycle observer callbacks are not currently dispatched.

## Testing and contributing

Override dependencies without changing production factories:

```dart
const greetingKey = ZenithKey<String>('greeting');
final container = ZenithTestContainerBuilder()
    .override(greetingKey, (_) => 'Hello from a test')
    .build();
```

Run the same checks as CI:

```sh
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze --fatal-infos
flutter test --coverage
flutter pub publish --dry-run
```

Standalone timing experiments belong in `benchmark/`, not ordinary test discovery:

```sh
flutter test benchmark/subscriber_benchmark.dart
```

Report defects through [GitHub issues](https://github.com/mihaimyh/flutter_zenith/issues) with a small public-API reproduction. See [migration notes](doc/audit-fixes.md) before upgrading applications that construct family keys manually or integrate tenant storage.

## License

[MIT](LICENSE).
