## 0.11.3 - Safe InheritedWidget Scope Resolution

* **`ZenithScopeProvider` Safe Resolution:** Replaced `dependOnInheritedWidgetOfExactType` with `getInheritedWidgetOfExactType` in `of()` and `maybeOf()`, allowing scopes to be safely inspected from any widget lifecycle stage (such as `initState`, `didChangeDependencies`, callbacks, or route bridges) without triggering framework assertion errors.
* **Modal Scope Bridge Hardening:** Enhanced `zenithShowModalBottomSheet` route tunneling to gracefully tunnel parent scopes without asserting when used outside a `ZenithScopeProvider` root.

## 0.11.2 - Native Soft-Fail Enhancements & Sanitized Diagnostics

* **`ZenithNode.trySet`:** Added typed `bool trySet(T newValue)` returning `false` when called on disposed nodes without emitting debug warnings.
* **Sanitized Disposed Node Diagnostics:** Sanitized `ZenithNode.set()` debug assert messages to avoid dumping payload objects or sensitive token data when late async writes land after scope teardown.

## 0.11.1 - Scope Bridge Resiliency & Optional Fallbacks

* **`ZenithScopeProvider.maybeOf`:** Added safe lookup method returning `ZenithTenantScope?` when called outside a scope provider boundary.
* **`zenithShowModalBottomSheet` Graceful Fallback:** Automatically resolves `ZenithScopeProvider.maybeOf` and preserves modal bottom sheets even if opened outside a tenant scope hierarchy.

## 0.11.0 - Multi-Tenant Scoping, Identity & Enterprise Policy Engine (`zenith_identity`)

* **Standalone Enterprise Barrel (`zenith_identity.dart`):** Added a dedicated entry point for multi-tenant scoping, identity management, policy-based authorization, and compliance isolation.
* **Scope Hierarchy & Lifetime Management (`ZenithScopeManager`):**
  - Added `ZenithScopeManager` supporting 3-tier hierarchy (`AppScope` → `UserScope` → `WorkspaceScope`).
  - **Zone-Based Captive Dependency Guard:** Traps singleton factories resolving scoped dependencies from child containers via Dart Zones (`#zenith_is_singleton_construction`), throwing `ZenithCaptiveDependencyException`.
  - Added `ZenithDrainable` and two-phase asynchronous scope teardown (`drainAndDispose`).
* **Identity Lifecycle & Migration Engine (`ZenithIdentityCoordinator`):**
  - Exhaustive sealed `ZenithAuthState` machine (`AuthUnauthenticated`, `AuthAnonymous`, `AuthAuthenticated<T>`, `AuthMigrating`, `AuthLocked`).
  - Dual-container anonymous-to-authenticated data migration with automatic transactional rollback on I/O error (`ZenithMigrationException`).
  - Biometric fast-lock session pausing (`lockSession` / `unlockSession`) keeping DB handles open.
  - Back-channel remote revocation listener and signal ingestion.
* **Partitioned Storage & Offline Outbox:**
  - `ZenithPartitionedStorage`: Per-tenant key-prefix isolation (`tenants/{id}/key`).
  - `ZenithOutboxEngine`: Tenant-isolated offline mutation queue with exponential backoff, clock-drift guards, and dead-letter queue isolation to prevent head-of-line blocking.
* **Policy-Based Authorization Engine:**
  - `ZenithPolicy`: Synchronous, reactive lambda, and asynchronous permission policies.
  - `ZenithRequirement`: Composite rules (`RoleRequirement`, `EntitlementRequirement`, `QuotaRequirement`).
  - `ZenithAuthorizeView`: Reactive widget with allocation-free `ZenithSubscriber` direct evaluation and `.hidden` / `.locked` builders.
  - `ZenithRouteGuard`: Route guard evaluator providing seamless redirection on denied access.
* **Widget Tree Scope Integration:**
  - `ZenithScopeProvider`: `InheritedWidget` boundary binding `ZenithTenantScope` to the widget tree.
  - `ZenithScopeBridge`: Route scope tunneling via `zenithShowModalBottomSheet` ensuring modal routes inherit parent container dependencies.
  - `ZenithAuthScope`: Declarative authentication UI switching with clean navigation unwinding before container disposal.
* **Concurrency & Task Abort:**
  - `ZenithCancellationToken`: One-shot cancellation signal triggered automatically on scope teardown.
  - `ZenithConcurrencyRunner`: Restartable and guarded async task runner supporting physical HTTP and I/O aborts.
* **Enterprise Compliance & Security:**
  - `Zeroizable`: Strictly-typed core interface for sensitive memory buffer zeroization with `0x00`.
  - `ZenithSecureBytes`: Cryptographic byte container with eager zeroization on node reassignment and automatic container wipe.
  - `ZenithDatabasePool`: Per-tenant physical SQLite database file isolation (`tenants/{id}/data.db`) with automatic drainable lifecycle binding.
  - `ZenithIpc`: Cross-isolate invalidation routing over `IsolateNameServer`.
* **Ergonomic Enhancements:**
  - Added `set value(T newValue)` on `ZenithNode` for direct assignment syntax alongside `node.set()`.
  - Added `ZenithMutation` and test helpers in `testing/zenith_test.dart`.

## 0.10.0

* **Controller Base Class (`ZenithController`):** Added a scoped base
  class for business logic with lifecycle hooks, mounted-safe node writes,
  async task handling, and stream subscriptions that clean up with its
  `ZenithRef`.
* **Stateful Widget Integration:** Added `ZenithStatefulWidget`,
  `ZenithState`, and `ZenithStateMixin` for reactive stateful widgets and
  lifecycle-safe, side-effect-only node listeners.
* **Inline Reactive Builder (`ZenithConsumer`):** Added a lightweight
  builder widget for reactive reads without creating a dedicated widget
  subclass.
* **Typed Key Families (`ZenithFamily`):** Added reusable typed key factories
  for argument-specific container dependencies.
* **Watch and Select Aliases:** Added `BuildContext.watch` and
  `BuildContext.select` as concise aliases for the existing node helpers.
* **Ref Disposal:** Container resets and disposal now clean up every active
  `ZenithRef`, including explicitly created refs.

## 0.9.0

* **`ZenithConsumerWidget`:** Ergonomic base widget providing `build(BuildContext context, ZenithRef ref)` for declarative, reactive consumption of Zenith nodes and container services without requiring nested `ZenithBuilder` widgets.
* **Side-Effect Listener (`ZenithListener`):** Dedicated widget for listening to state changes on a `ZenithNode<T>` and executing callbacks (e.g. navigation, notifications, snackbars, analytics) without causing widget rebuilds.
* **Ergonomic Ref/Context Extensions (`watchNode`, `selectNode`):** Added high-level extension methods on `ZenithRef` and `BuildContext` to watch nodes or project derived state selections with automatic lifecycle subscription cleanup.
* **`AsyncValue.hasValue`:** Added convenient boolean getter `hasValue` on `AsyncValue<T>` to quickly check if a value is present (both in data and previous loading/error states).
* **Cyclic Dependency Detection:** Added graph cycle detection in `ComputedNode` to safeguard against recursion loops during derived computation evaluations.

## 0.8.0

* **In-Memory Mediator (`ZenithMediator`):** MediatR equivalent supporting 1-to-1 Commands (`ZenithCommand<R>`), 1-to-Many Domain Events (`ZenithEvent`), and cross-cutting `ZenithPipelineBehavior` wrappers with re-entrancy depth safeguards and error isolation.
* **Resilience & Fault Handling (`ZenithResilience`):** Polly equivalent featuring `ZenithResiliencePipeline` with Exponential Backoff Retry (with randomized jitter to prevent thundering herd spikes), `CircuitBreaker` (`closed`, `open`, `halfOpen`), and sliding window `RateLimiter`.
* **Strongly-Typed Validation Engine (`ZenithValidator`):** FluentValidation equivalent with fluent rule builders (`notEmpty`, `email`, `minLength`, `greaterThan`, `must`), ReDoS safety, and `ZenithValidatedNode<T>` for auto-validating state nodes.
* **Structured Logger & Extensible Sinks (`ZenithLogger`):** Serilog equivalent supporting message template interpolation, automatic PII Redaction (`password`, `token`, `secret`, `credit_card`), `ConsoleSink`, and fixed-capacity `MemoryRingBufferSink` for zero OOM memory growth.

## 0.7.0

* **Feature Management & Feature Flags:** Introduced `ZenithFeature`, `FeatureNode`, and `ZenithFeatureBuilder` widget for reactive feature flag rollouts, Remote Config integration, and percentage rollout rule evaluation.
* **Options Pattern (`ZenithConfigNode<T>`):** Introduced dynamic configuration nodes (ASP.NET Core `IOptionsMonitor<T>` equivalent) that decode JSON/Map updates and notify subscribers only on parsed config changes.
* **Environment Profiles (`ZenithEnvironment`):** Added `ZenithEnvironment` (`development`, `staging`, `production`) and `environmentOverrides` to `ZenithContainer` for environment-aware DI registration.
* **Hosted Background Services (`ZenithService`):** Introduced lifecycle-managed background service contract (`onStart`, `onStop`) with concrete implementations `ZenithPeriodicService` (periodic background task runner) and `ZenithIsolateService` (background Isolate worker).

## 0.6.0

* **In-Place Scope Reset:** Added `ZenithContainer.reset()` to clear all nodes and references in an existing container without destroying the container instance itself (ideal for multi-user logout).
* **Authentication State Union:** Introduced `AuthState<T>` (`AuthUnauthenticated`, `AuthAuthenticating`, `AuthAuthenticated<T>`, `AuthError`) with exhaustive pattern matching and boolean status getters for router integration.
* **State Persistence & Hydration:** Introduced `ZenithStorage` interface, built-in `InMemoryStorage`, and `PersistedNode<T>` with static constructors (`PersistedNode.string`, `PersistedNode.integer`, `PersistedNode.boolean`) for auto-restoring and auto-saving node state across app restarts.
* **Node Middleware Pipeline:** Added `ZenithMiddleware<T>` interceptors (`onWillSet`, `onDidSet`) for value sanitization, validation, transformation, write blocking, and audit logging.

## 0.5.0

* **`AsyncValue` Equality & Value-Deduplication:** Implemented `==` and `hashCode` for `AsyncData`, `AsyncLoading`, and `AsyncError`. Setting the same async state twice now skips unnecessary subscriber notifications and widget rebuilds.
* **`AsyncValue` Convenience Helpers:** Added `maybeWhen`, `whenOrNull`, `hasData`, `requireValue`, and human-readable `toString()` methods.
* **Stream Support:** Added `ZenithStreamX.watchStream(node, stream)` and `StreamNodeX.watch(ref, stream)` for auto-subscribing streams to `AsyncValue` nodes with automatic lifecycle cancellation on scope disposal.
* **Computed / Derived Nodes:** Introduced `ComputedNode<T>` for reactive state derivation. Auto-tracks source node dependencies during evaluation and only re-notifies when the computed result changes.
* **Granular Subscriptions (`ZenithSelector`):** Introduced `ZenithSelector<T, R>` widget for selecting derived sub-properties of a node without triggering rebuilds when unrelated parts of the node change.
* **Framework Observer (`ZenithObserver`):** Added `ZenithObserver` and `ZenithLogObserver` for debugging node creation, mutation, and container lifecycle events.
* **Widget Rebuild Error Handling:** Added `errorBuilder` parameter to `ZenithBuilder` for graceful error rendering when builder closures throw.
* **Documentation & Metadata:** Comprehensive Dart doc coverage (`///`) across all public APIs and updated `pubspec.yaml` pub.dev metadata.

## 0.4.0

* Added `ConcurrencyStrategy` (`concurrent`, `droppable`, `restartable`) and
  `ZenithConcurrencyX.runAsyncGuarded<T>(node, task, {strategy})`: a
  race-condition-safe alternative to `ref.runAsync` for `AsyncValue<T>`
  nodes. `droppable` ignores new calls while a task is already loading
  (prevents double-submit on rapid taps); `restartable` (the default)
  drops stale results/errors from superseded calls so only the latest
  invocation can ever update state (fixes stale-response bugs in
  search-as-you-type / rapid tab switching).
* Added `ZenithIsolateX.runInIsolate<T, P>(node, payload, heavyComputation,
  {strategy})`: offloads a heavy synchronous computation to a background
  `Isolate` via `Isolate.run`, then writes the result through
  `runAsyncGuarded`, keeping the UI thread free of jank.
* Both extensions are additive -- `ZenithRef.runAsync` and
  `SafeAsyncNodeX.guard` are unchanged.

## 0.3.0

* Added `ZenithRef.set<T>(node, value)`: a mounted-safe write helper that
  silently no-ops once the ref's scope has been disposed.
* Added `ZenithRef.runAsync<T>(node, task)`: runs an async `task` and writes
  `AsyncLoading` / `AsyncData` / `AsyncError` to an `AsyncValue<T>` node,
  automatically guarding every mutation with the ref's mounted state so
  manual `if (!ref.isMounted) return;` checks are no longer required.
* Added `SafeAsyncNodeX.guard(ref, future)` extension on
  `ZenithNode<AsyncValue<T>>` as sugar over `ref.runAsync(...)`.
* **Breaking:** `ZenithNode.set()` no longer throws `StateError` when called
  on a disposed node; it now fails silently (a no-op), matching the
  semantics of a late/unmounted async write. Reading `.value`, calling
  `.invalidate()`, or `.subscribe()` on a disposed node still throw
  `StateError` as before.

## 0.2.0


* Added type-safe dependency keys with `ZenithKey<T>`.
* Added scoped factory overrides via `ZenithOverride<T>` and
  `ZenithContainer(overrides: [...])`.
* Added typed container APIs:
  `getOrCreate<T>(ZenithKey<T>, factory)`,
  `maybeReadKey<T>(ZenithKey<T>)`, and
  `invalidateKey<T>(ZenithKey<T>)`.
* Added `BuildContext` ergonomics via `ZenithContextX`:
  `context.container` and `context.zenith(...)`.
* Preserved backwards compatibility for existing string-key APIs
  (`getOrCreateNode`, `maybeNode`, `invalidate`).
* Added tests for key equality, typed node caching, and override behavior.

## 0.1.0

* Initial release of `flutter_zenith`.
* `ZenithContainer` / `ZenithRef`: container-scoped dependency injection with
  `getOrCreateNode`, `maybeNode`, `invalidate`, and disposal lifecycle hooks.
* `ZenithNode<T>`: atomic reactive state nodes with weak-reference subscriber
  tracking and automatic dead-subscriber pruning.
* `ZenithScope` / `ZenithBuilder`: Flutter widget integration for
  container-scoped state and surgical, dependency-tracked rebuilds.
* `AsyncValue<T>` (`AsyncData`, `AsyncLoading`, `AsyncError`): pattern-matching
  async state machine with `when`, `valueOrNull`, `isLoading`, and `hasError`.
* Comprehensive unit/widget test suite covering lifecycle, memory safety,
  reactive dependency graph, async/concurrency edge cases, and widget-tree
  integration.
