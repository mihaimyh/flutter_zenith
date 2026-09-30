---
name: flutter-zenith-state
description: Reactive state, widgets, and async work in flutter_zenith. Use when building UI that reads ZenithNode values, choosing between ZenithBuilder/ZenithSelector/ZenithListener/ZenithConsumerWidget, handling AsyncValue with runAsync/runAsyncGuarded/ZenithMutation, writing a ZenithController, watching streams, or adding computed state in a flutter_zenith app.
license: MIT
---

# flutter_zenith — state, widgets, and async

Read the parent `flutter-zenith` skill first. This skill covers the reactive core: nodes, derived state, widget subscriptions, and async/concurrency.

## ZenithNode fundamentals

```dart
final count = ZenithNode<int>(0);

count.value = 3;        // write (same as count.set(3))
final v = count.value;  // read
count.trySet(4);        // write, returns false if disposed instead of throwing
count.invalidate();     // notify subscribers WITHOUT changing the value
count.dispose();        // permanent; value/invalidate/subscribe then throw
```

- **Equal writes are no-ops.** `set` compares with `==` and skips notification. Two equal `AsyncData(sameUser)` values do not notify.
- Use `invalidate()` when the payload is unchanged but subscribers must re-read (mutable object mutated in place, an external gate flipped, an equal `AsyncData` must trigger an effect).
- Nesting guards: `invalidate()` is re-entrancy safe (nested calls are no-ops).
- Subscribers are held weakly. `subscribe(s)` returns a `ZenithSubscription`; retain the subscriber and call the handle to cancel.
- `set` on a disposed node is a safe no-op (late async writes don't crash). `value`, `subscribe`, `invalidate` throw on a disposed node.

## Reading state in widgets

Pick the smallest tool that fits.

| Tool | Use when |
| --- | --- |
| `ZenithBuilder(builder: (ctx) => …)` | Inline reactive subtree; auto-subscribes to every node read. Optional `errorBuilder(ctx, error, stack)`. |
| `ZenithConsumer(builder: (ctx, container, child) => …)` | Same, with the container passed in and an optional non-rebuilding `child`. |
| `ZenithConsumerWidget` | A whole widget whose `buildConsumer(ctx, container)` is auto-tracked. |
| `ZenithStatefulWidget` + `ZenithState` | You need local widget state; put reactive reads in `buildZenith(ctx, container)`. |
| `mixin ZenithStateMixin on State` | Add reactive helpers to an existing `State` without changing its base class. |
| `context.watch(node)` / `watchNode(node)` | Read a node in a tracked build (alias pair). |
| `context.select(node, (s) => s.field)` / `selectNode` | Read a field in a tracked build. Tracks the node (no extra dedupe). |
| `ZenithSelector<T, R>` | Rebuild only when a *selected* value changes. |

```dart
ZenithBuilder(builder: (context) {
  final name = context.select(userNode, (u) => u.displayName);
  return Text(name);
});
```

`ZenithStateMixin.listenNode` fires a callback on change without rebuilding; it is removed automatically on `dispose`:

```dart
class _MyState extends State<MyWidget> with ZenithStateMixin {
  @override
  void initState() {
    super.initState();
    listenNode(cartNode, (ctx, previous, current) {
      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Cart updated')));
    });
  }
}
```

`ZenithSelector` — the performance tool for list-heavy UI:

```dart
ZenithSelector<List<Item>, String>(
  node: itemsNode,
  selector: (items) => items[index].name,
  builder: (context, name) => Text(name),
);
```

`ZenithListener` — side effects only, never rebuilds:

```dart
ZenithListener<AsyncValue<String>>(
  node: saveNode,
  listener: (context, previous, current) {
    if (current.hasData) Navigator.of(context).pop();
  },
  child: const SaveButton(),
);
```

**Rule:** never trigger navigation/dialogs/snackbars inside a builder. Use `ZenithListener`.

## Computed state

```dart
final first = ZenithNode<String>('John');
final last  = ZenithNode<String>('Doe');
final full  = ComputedNode<String>(() => '${first.value} ${last.value}');
// first.value = 'Jane'  →  full.value == 'Jane Doe', downstream builders rebuild
full.dispose(); first.dispose(); last.dispose();
```

- Deps are collected **synchronously** during `_compute`. Reads after an `await` are not tracked.
- Never call `set` on a `ComputedNode` (throws). Don't write to its own dependencies (throws as a cycle).
- You own computed nodes: dispose them yourself. Disposing a container does not dispose arbitrary objects stored in nodes.

## Async state

`AsyncValue<T>` is a sealed union: `AsyncLoading(previousData?)`, `AsyncData(value)`, `AsyncError(error, stackTrace)`.

```dart
state.when(
  data: (v) => Text('$v'),
  loading: (previous) => previous != null ? Text('$previous') : const CircularProgressIndicator(),
  error: (e, st) => Text('Failed: $e'),
);
state.valueOrNull; state.requireValue; state.isLoading; state.hasData; state.hasError;
```

Write async results with lifecycle-safe helpers — never `setState` after an await:

```dart
// Basic: loading → data/error, guarded by ref lifetime.
await ref.runAsync(node, () async => await api.load());

// Node extension equivalent:
await node.guard(ref, () => api.load());

// Concurrency-guarded:
await ref.runAsyncGuarded(
  node,
  () async => await api.search(query),
  strategy: ConcurrencyStrategy.restartable, // search-as-you-type
);
```

`ConcurrencyStrategy`:

| Strategy | Behavior | Typical use |
| --- | --- | --- |
| `concurrent` (default for `runAsync`/`runInIsolate`) | Last completion wins | independent loads |
| `droppable` | Skip the new call while loading | prevent double-submit |
| `restartable` (default for `runAsyncGuarded`) | Supersede earlier calls; drop stale results | autocomplete, live filters |

Ignoring a completion does **not** cancel the underlying I/O (`ZenithConcurrencyRunner` does, via tokens).

Heavy synchronous work:

```dart
await ref.runInIsolate(node, payload, (p) => expensiveTransform(p));
// payload + callback must be isolate-sendable: no BuildContext, no ZenithRef closures.
```

User-initiated actions with pending state and error propagation:

```dart
final save = ZenithMutation<bool>(ref: ref, state: saveNode);
final ok = await save.run(() => api.submit());
// ok == null for stale/disposed runs; a current failure records AsyncError AND rethrows.
save.isPending; // saveNode.value.isLoading
```

## Streams

```dart
ref.watchStream(messagesNode, socket.stream); // auto-cancels on scope disposal
// or, from the node:
messagesNode.watch(ref, socket.stream);
```

Sets `AsyncLoading` immediately (preserving prior data), maps events to `AsyncData` and errors to `AsyncError`, and registers awaited cancellation on dispose. Returns the `StreamSubscription` if you need to pause/cancel early.

## Controllers

`ZenithController` is a base class for business logic bound to a ref scope:

```dart
class CartController extends ZenithController {
  CartController(super.ref);
  final itemsNode = ZenithNode<List<Item>>(const []);
  @override void onInit() => load();
  Future<void> load() => runAsync(stateNode, () => api.cart());
  // onDispose() runs when the owning scope is disposed/reset; set/runAsync/watchStream are mounted-safe.
}
```

Register it in a container factory so the ref drives its lifetime.

## Scope generations (stale work)

```dart
final guard = ZenithScopeGuard();
final token = guard.capture();
// later, on navigation/account/document change:
guard.invalidate();
if (token.isCurrent) node.value = lateResult; // discard otherwise
```

## Middleware (write interception)

```dart
class Clamp extends ZenithMiddleware<int> {
  @override
  int? onWillSet(ZenithNode<int> node, int current, int next) => next.clamp(0, 100);
  // return null to cancel the write entirely
}

final n = ZenithNode<int>(0, middleware: [Clamp()]);
```

Middleware returning `null` cancels the write — nullable node types must treat that as a real outcome. `onDidSet` runs after subscribers are notified.

## Recipes

**Form state + validity + submit** — see the package's `example/lib/expense_draft/` for a full pattern: one node per field, a derived validity node, and `ref.runAsync(submitResultNode, …)`.

**Optimistic list select** — `ZenithSelector` on the item, not the whole list node.

**Async save with dedupe** — `runAsyncGuarded(strategy: droppable)` and disable the button while `state.isLoading`.

## Gotchas

1. Reads must happen in the tracked synchronous build; a read after `await` won't subscribe.
2. Equal-set is silent — call `invalidate()` instead of re-setting.
3. `context.select`/`select` do not add a comparison boundary; use `ZenithSelector` for that.
4. `ZenithBuilder` rebuilds when **any** read node changes — split builders or use selectors to narrow.
5. Computed callbacks must be synchronous and side-effect free.
6. Stale results are dropped, not cancelled — use tokens/`ZenithConcurrencyRunner` to abort I/O.

## Reference

- [reference/api-reference.md](reference/api-reference.md) — exact signatures for every state API.
