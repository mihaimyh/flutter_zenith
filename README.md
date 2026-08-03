Here is a comprehensive, production-grade `README.md` designed specifically to serve two distinct audiences: **human developers** who want clean, readable documentation and **AI coding agents** (Cursor, Claude Code, Copilot, Devin) that need explicit structural rules, architectural guidelines, and code patterns to use `flutter_zenith` correctly without hallucinating non-existent APIs.

---

```markdown
# flutter_zenith

[![Flutter](https://img.shields.io/badge/Flutter-3.25%2B-02569B?logo=flutter)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.5%2B-0175C2?logo=dart)](https://dart.dev)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

A high-performance, container-scoped state management and dependency injection engine for Flutter. 

`flutter_zenith` merges **Container-Based Scoped Memory Isolation** (like Riverpod) with **Surgical Graph Reactivity** (like Signals) and **First-Class Async Lifecycle Guards** (like BLoC) into a single, zero-dependency engine.

## 🌟 Key Features

* **Surgical Rendering:** Widgets subscribe directly to atomic property nodes (`ZenithNode<T>`). Mutating a node re-renders *only* the listening `ZenithBuilder`—parent and sibling widgets remain completely idle.
* **Scoped Memory Isolation:** State resides inside a `ZenithContainer` bound to the widget tree via `ZenithScope`. Swapping or unmounting a scope automatically purges all contained state from memory.
* **Weak Reference Memory Safety:** Node subscriptions use `WeakReference` and automatic subscriber pruning to prevent memory leaks, even if a listener fails to unsubscribe.
* **Async Lifecycle Guards:** Built-in `AsyncValue<T>` state machines (`AsyncData`, `AsyncLoading`, `AsyncError`) paired with `ref.isMounted` execution tokens eliminate asynchronous post-disposal crashes.
* **Zero Dependencies:** Pure Dart/Flutter framework implementation—no `build_runner`, code generation, or third-party packages required.

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
    userProfileNode.set(AsyncLoading(userProfileNode.value.valueOrNull));
    try {
      final name = await Future.delayed(const Duration(seconds: 1), () => 'John Doe');
      
      // Always guard async state mutations with ref.isMounted
      if (!ref.isMounted) return; 
      
      userProfileNode.set(AsyncData(name));
    } catch (e, st) {
      if (!ref.isMounted) return;
      userProfileNode.set(AsyncError(e, st));
    }
  }
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

  @override
  Widget build(BuildContext context) {
    final container = ZenithScope.of(context);
    final controller = container.getOrCreateNode(
      'counterController', 
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

---

## 🤖 AI Agent Developer Instructions & Rules

If you are an AI coding assistant (Cursor, Claude Code, Copilot, Devin, etc.) generating or refactoring code for a project using `flutter_zenith`, **you must strictly adhere to the following rules**:

### Rule 1: Zero External State Management Dependencies

* Do NOT import or introduce `flutter_riverpod`, `signals`, `flutter_bloc`, `provider`, or `get_it`.
* Rely exclusively on `package:flutter_zenith/flutter_zenith.dart`.

### Rule 2: Memory & Async Safety

* **Async Execution Guards:** ALL asynchronous operations (`Future`, `Stream`, or `Timer` callbacks) MUST check `ref.isMounted` before setting or mutating any `ZenithNode` value.
* **Node Mutation Checks:** Do NOT attempt to read or mutate a disposed `ZenithNode`. Always ensure node disposal is handled through `ZenithContainer.dispose()` or `ref.onDispose()`.

```dart
// ✅ CORRECT AI PATTERN:
Future<void> loadData(ZenithRef ref) async {
  final result = await api.fetch();
  if (!ref.isMounted) return; // REQUIRED GUARD
  node.set(AsyncData(result));
}

// ❌ INCORRECT AI PATTERN (DO NOT GENERATE):
Future<void> loadData(ZenithRef ref) async {
  final result = await api.fetch();
  node.set(AsyncData(result)); // DANGEROUS: May execute post-disposal
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

```

```