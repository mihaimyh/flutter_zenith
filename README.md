# flutter_zenith

[![Flutter](https://img.shields.io/badge/Flutter-3.25%2B-02569B?logo=flutter)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.5%2B-0175C2?logo=dart)](https://dart.dev)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

A high-performance, container-scoped state management and dependency injection engine for Flutter. 

`flutter_zenith` merges **Container-Based Scoped Memory Isolation** (like Riverpod) with **Surgical Graph Reactivity** (like Signals) and **First-Class Async Lifecycle Guards** (like BLoC) into a single, zero-dependency engine.

## 🌟 Key Features

* **Type-Safe DI Keys:** `ZenithKey<T>` gives compile-time-safe dependency lookup, replacing string-only key workflows when desired.
* **Scoped Overrides:** `ZenithOverride<T>` lets tests and local scopes swap implementations without changing production factories.
* **Surgical Rendering:** Widgets subscribe directly to atomic property nodes (`ZenithNode<T>`). Mutating a node re-renders *only* the listening `ZenithBuilder`—parent and sibling widgets remain completely idle.
* **Scoped Memory Isolation:** State resides inside a `ZenithContainer` bound to the widget tree via `ZenithScope`. Swapping or unmounting a scope automatically purges all contained state from memory.
* **Weak Reference Memory Safety:** Node subscriptions use `WeakReference` and automatic subscriber pruning to prevent memory leaks, even if a listener fails to unsubscribe.
* **Async Lifecycle Guards:** Built-in `AsyncValue<T>` state machines (`AsyncData`, `AsyncLoading`, `AsyncError`) paired with automatic mounted-checks via `ref.set()` / `ref.runAsync()` eliminate asynchronous post-disposal crashes without manual `ref.isMounted` checks.
* **Concurrency & Isolate Guards:** `ref.runAsyncGuarded(node, task, strategy: ...)` solves race conditions between overlapping async calls (`droppable` for double-submit prevention, `restartable` for stale-response prevention), and `ref.runInIsolate(node, payload, heavyComputation)` offloads heavy synchronous work to a background `Isolate` without leaving the `AsyncValue` state machine.
* **Zero Dependencies:** Pure Dart/Flutter framework implementation—no `build_runner`, code generation, or third-party packages required.

### What Is New in 0.11.0

* **Enterprise Identity & Multi-Tenant Engine (`zenith_identity`):** Introduced a standalone entry point (`package:flutter_zenith/zenith_identity.dart`) delivering:
  - **Multi-Tenant Scope Hierarchy:** `ZenithScopeManager` supporting `AppScope` → `UserScope` → `WorkspaceScope` with Zone-based Captive Dependency Guards.
  - **Identity Coordinator:** Dual-container state migration with transactional rollback on I/O failure and biometric fast-lock session pausing.
  - **Partitioned Storage & Resilient Outbox:** Per-tenant disk storage namespacing and an offline outbox with exponential backoff and dead-letter isolation.
  - **Policy-Based Authorization Engine:** `ZenithPolicy`, composite `ZenithRequirement` rules, reactive `ZenithAuthorizeView`, and `ZenithRouteGuard`.
  - **Enterprise Security & Compliance:** Strictly-typed `Zeroizable` buffers (`ZenithSecureBytes`), physical SQLite DB file isolation (`ZenithDatabasePool`), and inter-isolate invalidation (`ZenithIpc`).
  - **Route Scope Bridge:** `zenithShowModalBottomSheet` for declarative scope inheritance across Flutter modal routes.

### What Was New in 0.8.0

* **In-Memory Mediator:** Introduced `ZenithMediator` (MediatR equivalent) for 1-to-1 Commands (`ZenithCommand`), 1-to-Many Domain Events (`ZenithEvent`), and `ZenithPipelineBehavior` wrappers.
* **Resilience Pipelines:** Added `ZenithResiliencePipeline` (Polly equivalent) with Exponential Backoff Retry (with randomized jitter), `CircuitBreaker`, and `RateLimiter`.
* **Fluent Validation Engine:** Added `ZenithValidator` (FluentValidation equivalent) with chainable rule builders and `ZenithValidatedNode<T>`.
* **Structured Logger & Extensible Sinks:** Introduced `ZenithLogger` (Serilog equivalent) with automatic PII Redaction and fixed-capacity `MemoryRingBufferSink`.

### What Was New in 0.7.0

* **Feature Management & Feature Flags:** Introduced `ZenithFeature`, `FeatureNode`, and `ZenithFeatureBuilder` widget for reactive feature flag rollouts and percentage rule evaluation.
* **Options Pattern:** Introduced `ZenithConfigNode<T>` (ASP.NET Core `IOptionsMonitor<T>` equivalent) for dynamic JSON/Map configuration decoding.
* **Environment Profiles:** Added `ZenithEnvironment` (`development`, `staging`, `production`) and environment-specific DI overrides in `ZenithContainer`.
* **Hosted Background Services:** Added `ZenithService` lifecycle worker contract with concrete implementations `ZenithPeriodicService` and `ZenithIsolateService`.

### What Was New in 0.6.0

* **In-Place Container Reset:** Added `container.reset()` to teardown all nodes and references in an existing container without destroying the container instance.
* **Auth State Machine:** Added `AuthState<T>` (`AuthUnauthenticated`, `AuthAuthenticating`, `AuthAuthenticated<T>`, `AuthError`) with exhaustive pattern matching and boolean status getters.
* **State Persistence:** Introduced `ZenithStorage` interface, `InMemoryStorage`, and `PersistedNode<T>` for auto-syncing state across app restarts.
* **Node Middleware:** Added `ZenithMiddleware<T>` interceptor pipeline (`onWillSet`, `onDidSet`) for value sanitization, write blocking, and audit logging.

### What Was New in 0.5.0

* **`AsyncValue` Value Equality:** Implemented `==` and `hashCode` for `AsyncData`, `AsyncLoading`, and `AsyncError`. Re-setting identical async values now skips unnecessary subscriber notifications and widget rebuilds. To force a re-notify with the same payload, use `ZenithNode.invalidate()` (or a dedicated signal / callback) — never `set(AsyncData(sameValue))` as a side-effect trigger.
* **Stream Integration:** Added `ref.watchStream(node, stream)` and `node.watch(ref, stream)` for auto-subscribing `Stream`s to `AsyncValue` nodes with automatic lifecycle teardown on scope disposal.
* **Computed Nodes:** Introduced `ComputedNode<T>` for derived state calculations with automatic source node dependency tracking and memoized invalidation.
* **Granular Subscriptions:** Added `ZenithSelector<T, R>` widget for selecting derived properties from a node, preventing rebuilds when unrelated fields change.
* **Framework Observer:** Added `ZenithObserver` and `ZenithLogObserver` for debugging node creation, mutations, and container disposal events.
* **Builder Error Handling:** Added `errorBuilder` parameter to `ZenithBuilder` for graceful error rendering when builder closures throw.

### What Was New in 0.4.0

* Added `ConcurrencyStrategy` (`concurrent`, `droppable`, `restartable`) and
  `ZenithConcurrencyX.runAsyncGuarded(node, task, {strategy})`: guards
  `AsyncValue<T>` nodes against race conditions from overlapping async
  calls -- `droppable` ignores new calls while one is already loading;
  `restartable` (the default) discards stale results from superseded calls.
* Added `ZenithIsolateX.runInIsolate(node, payload, heavyComputation,
  {strategy})`: runs a heavy computation on a background `Isolate` via
  `Isolate.run`, then writes the result through `runAsyncGuarded`.

### What Was New in 0.3.0

* Added `ZenithRef.set(node, value)` and `ZenithRef.runAsync(node, task)`: mounted-safe writes that silently no-op once the ref's scope is disposed, so you no longer need to manually check `ref.isMounted` after every `await`.
* Added the `SafeAsyncNodeX.guard(ref, future)` extension on `ZenithNode<AsyncValue<T>>` as sugar over `ref.runAsync(...)`.
* **Breaking:** `ZenithNode.set()` no longer throws `StateError` when called on a disposed node — it now fails silently (a no-op). Reading `.value`, calling `.invalidate()`, or `.subscribe()` on a disposed node still throw `StateError` as before.

### What Was New in 0.2.0

* Added `ZenithKey<T>` and typed container helpers: `getOrCreate`, `maybeReadKey`, `invalidateKey`.
* Added scoped overrides with `ZenithOverride<T>`.
* Added `BuildContext` helpers: `context.container` and `context.zenith(...)`.
* Existing string-key API remains supported for backwards compatibility.

---

## 📦 Installation & Setup

Add `flutter_zenith` to your `pubspec.yaml`:

```yaml
dependencies:
  flutter_zenith:
    path: ../flutter_zenith # or package version

```

Import the package in your Dart code:

```dart
import 'package:flutter_zenith/flutter_zenith.dart';

```

---

## 🚀 Quick Start Guide

### 1. Create State Nodes & Controllers

State in Zenith is encapsulated in `ZenithNode<T>` instances. For async workflows, use `AsyncValue<T>`:

```dart
class CounterController {
  // Synchronous atomic node
  final counterNode = ZenithNode<int>(0);

  // Async state node
  final userProfileNode = ZenithNode<AsyncValue<String>>(const AsyncLoading());

  void increment() {
    counterNode.set(counterNode.value + 1);
  }

  Future<void> fetchUser(ZenithRef ref) async {
    // ref.runAsync() automatically manages the loading/data/error
    // transitions and drops the result if the scope is disposed mid-flight
    // -- no manual `if (!ref.isMounted) return;` checks required.
    await ref.runAsync(userProfileNode, () {
      return Future.delayed(const Duration(seconds: 1), () => 'John Doe');
    });
  }
}

```

Prefer a more explicit call site? Use `ref.set()` for one-off mounted-safe writes:

```dart
Future<void> fetchUserManually(ZenithRef ref) async {
  final name = await api.fetchUser();
  ref.set(userProfileNode, AsyncData(name)); // Silently ignored if disposed.
}

```

#### Race Conditions & Double-Submits: `ref.runAsyncGuarded()`

When an async call can be triggered again before it finishes (rapid search
typing, a "Pay" button tapped twice), use `runAsyncGuarded` instead of
`runAsync`:

```dart
// Search-as-you-type: only the LATEST query is ever allowed to update state.
void onSearchQueryChanged(ZenithRef ref, String query) {
  ref.runAsyncGuarded(
    searchResultsNode,
    () => api.search(query),
    strategy: ConcurrencyStrategy.restartable, // default
  );
}

// Submit button: ignore rapid re-taps while a request is already in flight.
Future<void> submitPayment(ZenithRef ref) async {
  await ref.runAsyncGuarded(
    paymentStateNode,
    () => api.processPayment(),
    strategy: ConcurrencyStrategy.droppable,
  );
}

```

#### Heavy Computation Off the UI Thread: `ref.runInIsolate()`

For CPU-heavy synchronous work (large JSON parsing, crypto), offload it to a
background `Isolate` while keeping the same `AsyncValue` state machine:

```dart
Future<void> loadLargeDataset(ZenithRef ref, String rawJsonResponse) async {
  await ref.runInIsolate(
    datasetNode,
    rawJsonResponse,
    (json) {
      // Runs on a background Isolate -- keep this pure and self-contained;
      // do not close over ZenithRef, BuildContext, or other mutable state.
      final list = jsonDecode(json) as List;
      return list.map((item) => HeavyModel.fromJson(item)).toList();
    },
  );
}

```

### 2. Wrap the Scope in the Widget Tree

Bind state lifecycles to your widget hierarchy using `ZenithScope` and `ZenithContainer`:

```dart
class MyApp extends StatefulWidget {
  final String userId;
  const MyApp({super.key, required this.userId});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final ZenithContainer _container;

  @override
  void initState() {
    super.initState();
    _container = ZenithContainer();
  }

  @override
  Widget build(BuildContext context) {
    // Changing the ValueKey automatically disposes the old container and creates a clean scope
    return ZenithScope(
      key: ValueKey(widget.userId),
      container: _container,
      child: const MaterialApp(
        home: HomeScreen(),
      ),
    );
  }
}

```

### 3. Build Surgically Reactive UI

Use `ZenithBuilder` to read nodes. The builder automatically registers as a listener to any `ZenithNode` read inside its `builder` execution zone:

```dart
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static const counterControllerKey = ZenithKey<CounterController>(
    'counterController',
  );

  @override
  Widget build(BuildContext context) {
    final controller = context.zenith(
      counterControllerKey,
      (ref) => CounterController(),
    ).value;

    return Scaffold(
      appBar: AppBar(title: const Text('Zenith Counter')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // ONLY this ZenithBuilder rebuilds when counterNode changes
            ZenithBuilder(
              builder: (context) {
                final count = controller.counterNode.value;
                return Text('Count: $count', style: const TextStyle(fontSize: 24));
              },
            ),
            const SizedBox(height: 20),
            // Pattern-matching Async State
            ZenithBuilder(
              builder: (context) {
                return controller.userProfileNode.value.when(
                  loading: (prev) => Text('Loading... (Previous: $prev)'),
                  error: (err, stack) => Text('Error: $err'),
                  data: (name) => Text('Welcome, $name!'),
                );
              },
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: controller.increment,
        child: const Icon(Icons.add),
      ),
    );
  }
}

```

### Optional Scoped Overrides (Testing / Feature Scopes)

```dart
const counterKey = ZenithKey<CounterController>('counterController');

final container = ZenithContainer(
  overrides: [
    ZenithOverride<CounterController>(
      counterKey,
      (ref) => CounterController(),
    ),
  ],
);
```

---

## 🤖 AI Agent Developer Instructions & Rules

If you are an AI coding assistant (Cursor, Claude Code, Copilot, Devin, etc.) generating or refactoring code for a project using `flutter_zenith`, **you must strictly adhere to the following rules**:

### Rule 1: Zero External State Management Dependencies

* Do NOT import or introduce `flutter_riverpod`, `signals`, `flutter_bloc`, `provider`, or `get_it`.
* Rely exclusively on `package:flutter_zenith/flutter_zenith.dart`.

### Rule 2: Memory & Async Safety

* **Prefer `ref.runAsync()` / `ref.set()`:** ALL asynchronous operations (`Future`, `Stream`, or `Timer` callbacks) that write to a `ZenithNode` SHOULD use `ref.runAsync(node, task)` (for `AsyncValue<T>` nodes) or `ref.set(node, value)` (for plain nodes) instead of manually checking `ref.isMounted`. Both silently no-op once the ref's scope is disposed.
* **Use `ref.runAsyncGuarded()` for rapid-fire triggers:** If a `ZenithNode<AsyncValue<T>>` can be re-triggered before the previous call finishes (search-as-you-type, fast tab switching, a submit button tapped repeatedly), use `ref.runAsyncGuarded(node, task, strategy: ...)` instead of bare `ref.runAsync()`. Use `ConcurrencyStrategy.restartable` (default) so only the latest call's result lands, or `ConcurrencyStrategy.droppable` to ignore new calls while one is already loading.
* **Use `ref.runInIsolate()` for heavy synchronous work:** Large JSON parsing, crypto, or other CPU-bound transforms that would jank the UI thread SHOULD run via `ref.runInIsolate(node, payload, heavyComputation)`, not directly inside `runAsync`/`runAsyncGuarded`. Keep `heavyComputation` free of closures over `ZenithRef`, `BuildContext`, or other non-sendable state.
* **Manual guard as fallback:** If a helper isn't a good fit, checking `if (!ref.isMounted) return;` before mutation is still valid and supported.
* **Node Mutation Checks:** Do NOT attempt to read a disposed `ZenithNode` (`.value` throws `StateError`). Always ensure node disposal is handled through `ZenithContainer.dispose()` or `ref.onDispose()`. Note that `ZenithNode.set()` itself is a safe no-op on a disposed node (it does not throw), but `ref.runAsync()`/`ref.set()` remain the preferred, self-guarding entry points.
* **Equal `set` is not a signal:** `ZenithNode.set` short-circuits when `newValue == current` (including equal `AsyncData` / `AsyncLoading` / `AsyncError`). Do NOT re-set the same auth user / session payload to resume deferred work (scopes, sync, migration unlock). Use `node.invalidate()` to force `onNodeChanged`, or wire an explicit callback / dedicated signal node for the side effect.

```dart
// ✅ CORRECT AI PATTERN:
Future<void> loadData(ZenithRef ref) async {
  await ref.runAsync(node, () => api.fetch());
}

// ✅ ALSO CORRECT (manual write, still mounted-safe):
Future<void> loadDataManually(ZenithRef ref) async {
  final result = await api.fetch();
  ref.set(node, AsyncData(result));
}

// ❌ AVOID (unnecessary manual guard -- use ref.runAsync()/ref.set() instead):
Future<void> loadData(ZenithRef ref) async {
  final result = await api.fetch();
  if (!ref.isMounted) return;
  node.set(AsyncData(result));
}

```

### Rule 3: Surgical Building Constraints

* Wrap ONLY the minimal required widget subtree in a `ZenithBuilder`.
* Do NOT place `ZenithBuilder` at the root of large screen scaffolds unless every element on the screen depends on the read nodes.
* To prevent unnecessary observer zone leakage, perform all `ZenithNode.value` reads directly inside the `ZenithBuilder.builder` closure.

```dart
// ✅ CORRECT (Surgical):
Widget build(BuildContext context) {
  return Column(
    children: [
      const StaticHeaderWidget(), // Will NOT rebuild
      ZenithBuilder(
        builder: (context) => Text(node.value), // ONLY this rebuilds
      ),
    ],
  );
}

// ❌ INCORRECT (Broad Rebuild):
Widget build(BuildContext context) {
  return ZenithBuilder(
    builder: (context) {
      return Column(
        children: [
          const StaticHeaderWidget(), // Rebuilds unnecessarily
          Text(node.value),
        ],
      );
    },
  );
}

```

### Rule 4: Container & Scope Management

* Access the active container via `ZenithScope.of(context)`.
* Use `ZenithContainer.getOrCreateNode(key, factory)` to instantiate controllers or services.
* Always assign a distinct `ValueKey` to `ZenithScope` when user sessions change (e.g., login/logout) to force container teardown and prevent state cross-contamination.

---

## 📂 Package Architecture & Directory Structure

```
flutter_zenith/
├── lib/
│   ├── flutter_zenith.dart            # Core reactive & DI framework barrel
│   ├── zenith_identity.dart           # Multi-tenant scoping & identity barrel
│   ├── core/                          # Primitives (Nodes, Containers, AsyncValue, Zeroizable)
│   ├── testing/                       # Test utilities (ZenithTestContainer, ZenithMutation)
│   └── src/                           # Enterprise features
│       ├── scope/                     # ScopeManager, UserScope, Drainable, IPC
│       ├── identity/                  # Auth state machine, IdentityCoordinator
│       ├── storage/                   # Partitioned storage driver, Outbox engine
│       ├── authorization/             # Policy engine, AuthorizeView, RouteGuard
│       ├── widgets/                   # ScopeProvider, ScopeBridge, AuthScope
│       ├── concurrency/               # CancellationToken, ConcurrencyRunner
│       └── enterprise/                # DatabasePool, SecureBytes
├── test/
│   ├── core/                          # Core reactive & DI test suites
│   ├── scope/                         # Scope isolation & Captive Guard tests
│   ├── identity/                      # Migration & state machine tests
│   ├── storage/                       # Partitioned storage & outbox tests
│   ├── authorization/                 # Policy engine & AuthorizeView tests
│   ├── widgets/                       # Scope bridge & navigation unwind tests
│   ├── concurrency/                   # Cancellation token & HTTP abort tests
│   ├── enterprise/                    # Zeroization & DB isolation tests
│   └── advanced/                      # IPC, 3-tier hierarchy & route guard tests
└── example/                           # Runnable demo app

```

---

## 🧪 Running Tests & Benchmarks

Run the complete framework test suite:

```bash
flutter test

```

Run static code analysis:

```bash
flutter analyze

```

Run the runnable example application:

```bash
cd example
flutter pub get
flutter run

```

---

## 📜 License

Distributed under the MIT License. See `LICENSE` for more information.