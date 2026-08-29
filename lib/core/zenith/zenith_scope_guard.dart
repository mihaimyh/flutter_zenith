/// A version token that invalidates asynchronous work when its logical scope
/// changes, such as navigating away, switching accounts, or selecting another
/// document.
///
/// The guard has no application-specific identity. Owners call [invalidate]
/// whenever work from the previous scope must no longer affect state.
class ZenithScopeGuard {
  int _generation = 0;

  /// Captures a token for the current logical scope.
  ZenithScopeToken capture() => ZenithScopeToken._(this, _generation);

  /// Invalidates all tokens captured before this call.
  void invalidate() {
    _generation++;
  }
}

/// An immutable snapshot of a [ZenithScopeGuard]'s current generation.
class ZenithScopeToken {
  const ZenithScopeToken._(this._guard, this._generation);

  final ZenithScopeGuard _guard;
  final int _generation;

  /// Whether work associated with this token may still update state.
  bool get isCurrent => _guard._generation == _generation;
}