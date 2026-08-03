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
* **Zero Dependencies:** Pure Dart/Flutter framework implementation—no `build_runner`, code generation, or third-party packages required.

### What Is New in 0.3.0

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
* **Manual guard as fallback:** If a helper isn't a good fit, checking `if (!ref.isMounted) return;` before mutation is still valid and supported.
* **Node Mutation Checks:** Do NOT attempt to read a disposed `ZenithNode` (`.value` throws `StateError`). Always ensure node disposal is handled through `ZenithContainer.dispose()` or `ref.onDispose()`. Note that `ZenithNode.set()` itself is a safe no-op on a disposed node (it does not throw), but `ref.runAsync()`/`ref.set()` remain the preferred, self-guarding entry points.

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
│   ├── flutter_zenith.dart            # Main export barrel file
│   └── core/
│       └── zenith/
│           ├── async_value.dart       # AsyncValue state machine (Data, Loading, Error)
│           ├── zenith_node.dart        # Atomic reactive nodes with WeakRef tracking
│           ├── zenith_container.dart   # Memory DI container, ref lifecycle, & scoping
│           ├── zenith_widgets.dart     # ZenithScope & surgical ZenithBuilder
│           └── zenith_core.dart       # Internal framework barrel
├── test/
│   └── core/
│       └── zenith/
│           ├── zenith_lifecycle_test.dart        # Teardown & isMounted validation
│           ├── zenith_memory_test.dart           # Weak reference & GC pruning tests
│           ├── zenith_widget_test.dart           # Rebuild isolation verification
│           ├── zenith_scope_test.dart            # Scope swap & disposal tests
│           └── zenith_benchmark_widget_test.dart # High-load stress & performance tests
└── example/                            # Runnable demo app

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