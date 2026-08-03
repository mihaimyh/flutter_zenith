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
