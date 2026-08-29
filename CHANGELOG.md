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
