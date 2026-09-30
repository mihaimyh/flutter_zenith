---
name: flutter-zenith
description: Overview of the flutter_zenith Flutter package — container-scoped reactive state management and dependency injection. Use when starting work in a project that depends on flutter_zenith, when choosing which Zenith API to use, or when the user mentions flutter_zenith, ZenithNode, ZenithContainer, ZenithScope, ZenithBuilder, ZenithKey, or zenith_identity.
license: MIT
---

# flutter_zenith — package overview

Entry point for building Flutter apps with `flutter_zenith`. Read this first, then load the focused skill for the area you are implementing.

## What it is

`flutter_zenith` is a **container-scoped reactive state + DI engine**. Widgets subscribe to the exact nodes they read; containers own dependencies and their cleanup. No code generation, no runtime deps beyond the Flutter SDK. Requires Dart 3.12.2+ (within Dart 3).

It is a Flutter package, not a Dart server/CLI library. Isolate and IPC features need platforms that support those APIs.

## Install and imports

```sh
flutter pub add flutter_zenith
```

```dart
// Core: nodes, containers, widgets, app utilities, test helpers.
import 'package:flutter_zenith/flutter_zenith.dart';

// Identity: scopes, public identity, policies, outbox, tenant DB pool.
// Use a prefix when importing both — the two libraries expose distinct auth
// state types AND a different BuildContext.zenith extension.
import 'package:flutter_zenith/zenith_identity.dart' as identity;
```

## Mental model (60 seconds)

- `ZenithNode<T>` — an observable value cell. `.value` reads; `.set(v)` / `.value = v` writes; equal writes are **no-ops**; `invalidate()` forces a notification without changing the value.
- `ZenithBuilder` — runs its builder and auto-subscribes to every node read inside it. Rebuilds only when those nodes change.
- `ZenithContainer` — owns nodes and their lifecycle. `getOrCreate(key, factory)` caches per container.
- `ZenithScope` — puts a container into the widget tree; `context.container` retrieves it and **disposes the container when removed**.
- `ComputedNode` — derives a value from other nodes and re-runs when they change.
- `AsyncValue` — sealed loading/data/error union for async work; write it via `ref.runAsync` / `runAsyncGuarded` / `ZenithMutation`.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_zenith/flutter_zenith.dart';

const counterKey = ZenithKey<int>('counter');

void main() {
  final container = ZenithContainer(); // create OUTSIDE build
  runApp(ZenithScope(
    container: container,
    child: const MaterialApp(home: CounterScreen()),
  ));
}

class CounterScreen extends StatelessWidget {
  const CounterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final counter = context.container.getOrCreate(counterKey, (_) => 0);
    return Scaffold(
      body: Center(child: ZenithBuilder(builder: (_) => Text('${counter.value}'))),
      floatingActionButton: FloatingActionButton(
        onPressed: () => counter.value++,
        child: const Icon(Icons.add),
      ),
    );
  }
}
```

## Pick the right skill

| You are building… | Load skill |
| --- | --- |
| Reactive state, widgets, async work, controllers, streams, concurrency | `flutter-zenith-state` |
| Containers, node keys, DI/families, overrides, lifecycle, background services, tests | `flutter-zenith-di` |
| Persistence, config, feature flags, validation, mediator, resilience, logging, observers, middleware | `flutter-zenith-appkit` |
| Multi-tenant scopes, auth, authorization, tenant storage, outbox, tenant DB, cancellation, secure buffers | `flutter-zenith-identity` |
| Full API surface / feature catalog | [reference/feature-catalog.md](reference/feature-catalog.md) |

## Golden rules (violating these causes most bugs)

1. **Create containers outside `build`.** `ZenithScope` disposes the container it owns; never place the same owned container in two independent `ZenithScope`s.
2. **Read `.value` synchronously inside a builder/consumer to subscribe.** Reads after an `await` are not tracked as dependencies.
3. **Equal writes are silently dropped.** Use `invalidate()` to re-notify without a value change (e.g. same `AsyncData` must fire an effect).
4. **`getOrCreate` caches locally only.** Use `maybeReadKey(key)` to search the parent chain; local resolution does not inherit every parent dependency.
5. **Keep `ComputedNode` callbacks synchronous** and never write to their own dependencies. Direct `set` on a computed node throws.
6. **Manual subscribers are held weakly.** Retain the subscriber and call the returned `ZenithSubscription` cancellation handle when done.
7. **Directly created nodes need explicit ownership.** `computed` and `persisted` nodes must be disposed by you; disposing a container does not recursively dispose arbitrary objects stored in nodes.
8. **Use mounted-safe async.** `ref.runAsync`, `ref.runAsyncGuarded`, `node.guard`, or `ZenithMutation` — never raw `setState` after an await.
9. **Register cleanup, then await it.** `ref.onDispose` (sync) / `ref.onDisposeAsync` (async); observe `container.disposeAsync()` / `disposalComplete`.
10. **Filter rebuilds deliberately.** `ZenithSelector` rebuilds on a selected value change; `ZenithListener` runs side effects without rebuilding. `context.select` tracks reads but does **not** provide that comparison boundary.
11. **Never reconstruct family keys by hand.** Always call `family(argument)`; arguments need stable `==`/`hashCode`.
12. **`PersistedNode` reads synchronously.** Async backends need preloading/caching or a separate hydration flow.

## Choosing core vs identity

- Use **core** (`flutter_zenith.dart`) for single-user reactive state + DI.
- Add **identity** (`zenith_identity.dart`) only when you need app/user/workspace scope lifecycles, an auth state machine, policy authorization, per-tenant storage, an offline outbox, or per-tenant databases. It builds on the core container engine.

## Installing these skills for other projects

This repo's `.agents/skills/` is the source of truth. When building a *separate* app that depends on `flutter_zenith`, copy the skills to your personal skills directory once:

```powershell
Copy-Item -Recurse -Force .agents\skills\flutter-zenith* "$env:USERPROFILE\.agents\skills\"
```

Keep the repo copy authoritative; re-copy after editing here.

## Reference

- [reference/feature-catalog.md](reference/feature-catalog.md) — the complete capability catalog (core + identity) with the public API for each capability.
- `README.md` in the package root for the same catalog with extended prose.
