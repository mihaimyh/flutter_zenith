---
name: flutter-zenith-di
description: Dependency injection, containers, keys, families, overrides, lifecycle, and background services in flutter_zenith. Use when wiring a ZenithContainer into an app, registering typed dependencies with ZenithKey/ZenithFamily, adding ZenithOverride or environmentOverrides, managing node/ref cleanup, hosting ZenithService/PeriodicService/IsolateService, or overriding dependencies in tests.
license: MIT
---

# flutter_zenith — dependency injection & lifecycle

Read the parent `flutter-zenith` skill first. This skill covers containers, DI, families, lifecycle, services, and testing.

## Container and scope setup

```dart
void main() {
  final container = ZenithContainer(); // create ONCE, outside build
  runApp(ZenithScope(container: container, child: const App()));
}
```

- `ZenithScope` disposes the container it owns when removed, and disposes the **old** container when replaced with a different one.
- Never put the same owned container into two independent `ZenithScope`s.
- `context.container` (or `ZenithScope.of(context)`) retrieves the container; both assert a non-disposed scope exists.

## Typed dependencies and keys

```dart
const nameKey = ZenithKey<String>('displayName');

final name = container.getOrCreate(nameKey, (ref) => 'Guest');
// or untyped string keys:
final count = container.getOrCreateNode<int>('counter', (ref) => 0);
```

`ZenithKey<T>` equality includes the type parameter **and** the name, so `ZenithKey<int>('count')` and `ZenithKey<String>('count')` never collide. Key equality compares exact runtime type.

`getOrCreate` caches locally. To look up an ancestor's registration explicitly:

```dart
final parentNode = container.maybeReadKey(nameKey); // walks parent chain
final localOnly  = container.maybeNode<String>(nameKey); // no parent fallback
container.invalidateKey(nameKey); // invalidate; bubbles to parent if not local
```

Local registration does **not** automatically inherit every parent dependency — use `maybeReadKey` when you want hierarchy.

## Overrides and environments

```dart
const nameKey = ZenithKey<String>('displayName');

final container = ZenithContainer(
  environment: ZenithEnvironment.staging,
  overrides: [ZenithOverride(nameKey, (_) => 'Test account')],
  environmentOverrides: {
    ZenithEnvironment.development: [ZenithOverride(nameKey, (_) => 'Dev account')],
  },
);

container.getOrCreate(nameKey, (_) => 'Guest').value; // 'Dev account' in development
```

Environment-specific overrides take precedence over general `overrides`.

## Parameterized dependencies (families)

```dart
const profile = ZenithFamily<String, String>('profile');

final alice = container.getOrCreate(profile('alice'), (_) => 'Alice');
final registry = profile.registry();
registry.key('alice');                 // stable key for an argument
registry.invalidateAll(container);     // batch-invalidate tracked keys
registry.forgetAll();                  // stop tracking (does NOT remove nodes)
```

- Always call `family(argument)`. Never reconstruct `ZenithKey('family#argument')`.
- Family identity = value type + argument type + family name + argument equality/hash. Arguments must have stable `==`/`hashCode` while used as keys.
- The registry owns keys only; node ownership stays with the container. `forgetAll` does not delete container nodes.

## `ZenithRef` — scoped lifecycle handle

Each node created via `getOrCreate`/`getOrCreateNode` gets its own `ZenithRef`:

```dart
final settings = container.getOrCreate<Settings>(settingsKey, (ref) {
  final client = HttpClient();
  ref.onDispose(client.close);                       // sync cleanup
  ref.onDisposeAsync(() => cache.flush());           // awaited cleanup
  return Settings(client);
});

// later, mounted-safe writes:
settingsRef.set(settingsNode, next);      // no-op after disposal
await settingsRef.runAsync(asyncNode, () => api.load());
```

- `ref.isMounted` — container alive?
- `ref.onDispose` — if the ref is already disposed, the callback runs immediately.
- `ref.onDisposeAsync` — registered for `disposeAsync` / `disposalComplete`.
- A factory that **throws** disposes its registered resources before rethrowing. Do not rely on failed init skipping cleanup.

## Teardown

```dart
await container.disposeAsync();     // sync dispose + await all async cleanup
// or:
container.dispose(purgeZeroize: true);
await container.disposalComplete;
```

`reset()` fires ref dispose callbacks and disposes nodes, clears internal maps, awaits cleanup, but keeps the container **reusable** (in-place logout/session teardown). `dispose` is idempotent; `reset` is a no-op on a disposed container.

**Ownership rule:** disposing a container does not recursively dispose arbitrary objects stored inside a node. Directly created `ComputedNode`/`PersistedNode` must be disposed by you.

## Background services

```dart
class SyncService extends ZenithService {
  @override Future<void> onStart(ZenithRef ref) async { /* open socket */ }
  @override Future<void> onStop() async { /* teardown */ }
}

final reg = ref.registerService(SyncService());   // ZenithServiceRegistration
await reg.started;          // completes on success, throws its error
reg.lastError;              // most recent lifecycle failure
await reg.stop();           // idempotent; waits for startup before stopping
```

- `ZenithPeriodicService(interval:, task:)` — `Timer.periodic`, never overlaps tasks; shutdown waits for an in-flight task; failures recorded in `lastError` (they don't escape the timer).
- `ZenithIsolateService<T, R>(entryPoint:, onData:)` — spawns/kills a background isolate on start/stop; `isAlive` reflects state.

## Testing

```dart
final container = ZenithTestContainerBuilder()
    .override(nameKey, (_) => 'Hello from a test')
    .build();

expect(container.getOrCreate(nameKey, (_) => 'prod').value, 'Hello from a test');
```

`build({ZenithContainer? parent})` creates the container in `ZenithEnvironment.development` with your overrides. `InMemoryStorage` (from appkit) covers persistence tests.

## Recipes

**App-wide container with env overrides** — build once in `main`, wrap in `ZenithScope`, pass into services.

**Scoped feature container** — create a child `ZenithContainer(parent: appContainer)` for a feature and pass it to a nested `ZenithScope`; the parent provides shared deps via `maybeReadKey`.

**Per-argument cache** — `ZenithFamily` + a registry per scope; invalidate all keys on a data refresh.

## Gotchas

1. Create containers outside `build`. `ZenithScope` owns what you give it.
2. `getOrCreate` caches per container; two containers produce two independent nodes for the same key.
3. Only `maybeReadKey`/`invalidate` walk the parent chain.
4. Family arguments need stable equality — do not use mutable objects whose hash changes.
5. Register async cleanup with `onDisposeAsync`; `dispose()` alone does not wait for it — await `disposalComplete`/`disposeAsync()`.
6. Failed factories still release already-registered resources.
7. Background-service shutdown waits for startup, then stops exactly once.

## Reference

- [reference/api-reference.md](reference/api-reference.md) — exact signatures for containers, keys, refs, services, and test helpers.
