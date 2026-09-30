# flutter_zenith — feature catalog

Complete capability map. "Contract" notes the non-obvious behavior an agent must respect.

## Core library (`package:flutter_zenith/flutter_zenith.dart`)

| Capability | Public APIs | Contract |
| --- | --- | --- |
| Reactive values | `ZenithNode`, `ZenithSubscriber`, `ZenithSubscription`, `ZenithObserverTracker`, `ZenithZone` | Synchronous notifications; equality-based write suppression; subscribers held via `WeakReference` and auto-pruned; `subscribe` returns a cancellation handle. |
| Derived state | `ComputedNode` | Auto-tracks synchronous source reads; reconciles changing deps; `set` throws `StateError`; cyclic deps throw. |
| Dependency injection | `ZenithContainer`, `ZenithRef`, `ZenithKey`, `ZenithOverride`, `NodeKey` | Typed factories, cached nodes, scoped cleanup, explicit parent lookup. |
| Parameterized dependencies | `ZenithFamily`, `ZenithFamilyRegistry` | Argument-based keys; identity = value type + arg type + family name + arg equality; tracked invalidation; registry cleanup. |
| Environment configuration | `ZenithEnvironment`, `environmentOverrides` | Select development/staging/production overrides at container construction; env overrides beat general overrides. |
| Reactive widgets | `ZenithScope`, `ZenithBuilder`, `ZenithConsumer`, `ZenithConsumerWidget` | Container access + dependency-driven builds; optional `errorBuilder`. |
| Stateful integration | `ZenithStatefulWidget`, `ZenithState`, `ZenithStateMixin`, `ZenithController` | Widget/controller lifecycle; `listenNode` imperative listeners. |
| Selection and effects | `ZenithSelector`, `ZenithListener`, `watch`, `select`, `watchNode`, `selectNode` | `ZenithSelector` filters by selected-value equality; listeners for side effects. |
| Safe scheduling | `ZenithSafeRebuild` | Defers/coalesces rebuilds requested during build/layout/paint. |
| Async state | `AsyncValue`, `AsyncData`, `AsyncLoading`, `AsyncError`, `SafeAsyncNodeX` | Exhaustive `when`/`maybeWhen`/`whenOrNull`; `valueOrNull`, `requireValue`, `hasData`, `isLoading`, `hasError`, `hasValue`; value equality. |
| Async operations | `runAsync`, node `guard`, `ZenithMutation` | Mounted-safe writes; mutations reject stale results and rethrow current failures. |
| Concurrency | `runAsyncGuarded`, `ConcurrencyStrategy`, `runInIsolate` | concurrent / droppable / restartable; explicit isolate offload. |
| Scope generations | `ZenithScopeGuard`, `ZenithScopeToken` | Capture/invalidate tokens for work spanning scope changes. |
| Streams | `watchStream` (on `ZenithRef`), `watch` (on async nodes) | Stream data/errors → async state; cancellation joins async cleanup. |
| Persistence | `PersistedNode`, `ZenithStorage`, `InMemoryStorage` | Synchronous hydration; ordered async writes; `flush()` and `persistenceError`. |
| Middleware | `ZenithMiddleware` | Transform/cancel writes (`onWillSet`); observe accepted writes (`onDidSet`). |
| Core auth model | `AuthState`, `AuthUnauthenticated`, `AuthAuthenticating`, `AuthAuthenticated`, `AuthError` | Sealed data model (distinct from identity's `ZenithAuthState`). |
| Configuration | `ZenithConfigNode` | `updateRaw(map)` decodes into typed config via a supplied decoder. |
| Feature flags | `ZenithFeature`, `FeatureNode`, `ZenithFeatureBuilder` | Boolean state + deterministic `percentageRollout`. |
| Validation | `ZenithValidator`, `PropertyRuleBuilder`, `ValidationResult`, `ValidationError`, `ZenithValidatedNode` | Fluent rules (`notEmpty`, `email`, `minLength`, `greaterThan`, `must`); per-field errors. |
| Messaging | `ZenithMediator`, `ZenithCommand`, `ZenithEvent`, `ZenithPipelineBehavior` | One command handler; sequential event handlers (errors debug-logged); depth limit 10; `container.mediator` / `ref.mediator`. |
| Resilience | `ZenithResiliencePipeline`, `CircuitState`, `runResilient` | Retry/backoff/jitter, circuit breaker, monotonic sliding-window limiter. Rate limit counts admitted executions; retries happen inside one execution. |
| Background services | `ZenithService`, `ZenithPeriodicService`, `ZenithIsolateService`, `ZenithServiceRegistration`, `registerService` | Observable start/stop; non-overlapping periodic tasks; scoped isolate lifetime. |
| Logging | `ZenithLogger`, `ZenithLogSink`, `ConsoleSink`, `MemoryRingBufferSink`, `ZenithLogLevel`, `ZenithLogEvent` | Structured events; top-level PII redaction (not recursive); bounded in-memory logs; `container.logger`. |
| Diagnostics | `ZenithObserver`, `ZenithLogObserver`, `Zenith.observer`, `Zenith.onDebugPrint` | Mutation/container observation; opt-in debug output. Other lifecycle observer methods are declared but not dispatched. |
| Sensitive values | `Zeroizable` | Opt-in buffer overwrite on replacement or explicit purge. |
| Testing | `ZenithTestContainerBuilder` | Build containers with typed overrides. |

## Identity library (`package:flutter_zenith/zenith_identity.dart`)

Re-exports core `ZenithKey`, `ZenithNode`, `AsyncValue` to avoid double imports.

| Capability | Public APIs | Contract |
| --- | --- | --- |
| Scope ownership | `ZenithScopeManager`, `ZenithTenantScope`, `ZenithUserScope`, `ZenithLifetime` | App/user/workspace lifetimes; captive-dependency detection for scoped deps. |
| Draining | `ZenithDrainable`, `ZenithDrainableCallback`, `drainAndDispose` | Drain before disposal, then await registered async cleanup. |
| Identity transitions | `ZenithIdentityCoordinator`, `ZenithAuthState`, `ZenithMigrationException` | Anonymous sessions, account upgrades, sign-in/out, stale-migration protection. |
| Lock and revocation | `AuthLocked`, `lockSession`, `unlockSession`, `RevocationReason`, `ingestRemoteRevocation` | Lock-screen state; app-supplied remote revocation events (no server connection). |
| Tenant storage | `StorageDriver`, `InMemoryStorageDriver`, `ZenithPartitionedStorage` | Async storage with independently percent-encoded tenant/key namespaces. |
| Outbox | `ZenithOutboxEngine`, `OutboxMutation` | In-memory tenant-filtered dispatch, stable IDs, retry/backoff, dead letters. |
| Policies | `ZenithPolicy`, `PolicyRef`, `ZenithRequirement`, `UserSecurityContext` | Custom predicates plus auth, entitlement, role and bandwidth requirements. |
| Authorization | `ZenithAuthorizationService`, `AuthorizationResult`, `ZenithRouteGuard` | Fail-closed evaluation; redirect decisions. |
| Conditional UI | `ZenithAuthorizeView`, `.hidden`, `.locked` | Authorized/denied/pending views; reactive via `PolicyRef.watch`. |
| Scope widgets | `ZenithScopeProvider`, `ZenithAuthScope` | Scope access and account-specific subtree replacement. Provider does not own disposal. |
| Modal bridge | `zenithShowModalBottomSheet` | Forward the current scope into a modal route. |
| Cancellation | `ZenithCancellationToken`, `ZenithConcurrencyRunner`, `runWithToken`, `runGuarded` | Cooperative cancellation with callbacks for physical I/O abort. |
| Database ownership | `ZenithDatabasePool`, `ZenithDatabaseHandle`, `InMemoryDatabasePool` | Driver-supplied tenant handles; shared concurrent acquisition; awaited release. |
| Secure buffers | `ZenithSecureBytes` | Overwrites a caller-supplied byte buffer; no encryption/copy protection. |
| Inter-isolate invalidation | `ZenithInvalidateMessage`, `listenToInterIsolateInvalidations` | Tenant-filtered invalidation via `IsolateNameServer`. |
| Background bootstrap | `ZenithScopeManager.bootstrapHeadless` | Create a scope for background work without building widgets. |

## Async state type map (two distinct hierarchies)

| Purpose | Core `AuthState<T>` | Identity `ZenithAuthState` |
| --- | --- | --- |
| Not signed in | `AuthUnauthenticated` | `AuthUnauthenticated` |
| Signing in / guest | `AuthAuthenticating` | `AuthAnonymous(anonId)` |
| Signed in | `AuthAuthenticated(user)` | `AuthAuthenticated(session)` |
| In transition | — | `AuthMigrating(fromId, toId)` |
| Biometric lock | — | `AuthLocked(session)` |
| Failure | `AuthError(error, stackTrace)` | — |

Both libraries declare `AuthUnauthenticated` / `AuthAuthenticated`, so use the `identity.` prefix when importing both.
