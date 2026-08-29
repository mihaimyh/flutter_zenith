/// Abstraction for objects that can perform bounded-time cleanup work before
/// a tenant scope is finally destroyed.
///
/// Register instances via [ZenithTenantScope.registerDrainable]. When
/// [ZenithScopeManager.endScopeAsync] is called, all drainables are awaited
/// (with a bounded timeout) before the scope container is disposed.
///
/// Typical use-cases:
/// - Flushing a pending SQLite write transaction.
/// - Completing an in-flight HTTP mutation from the outbox.
/// - Persisting unsaved user preferences to disk.
abstract class ZenithDrainable {
  /// Performs the cleanup/flush work.
  ///
  /// Must complete within the timeout window passed to
  /// [ZenithScopeManager.endScopeAsync]. If it does not, the scope is
  /// forcibly disposed anyway.
  Future<void> drain();
}

/// A convenience [ZenithDrainable] backed by a plain async callback.
class ZenithDrainableCallback implements ZenithDrainable {
  /// The async callback invoked by [drain].
  final Future<void> Function() _callback;

  /// Creates a [ZenithDrainableCallback] from [callback].
  ZenithDrainableCallback(this._callback);

  @override
  Future<void> drain() => _callback();
}
