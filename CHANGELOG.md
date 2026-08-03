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
