import 'zenith_scope_manager.dart';

/// A [ZenithTenantScope] extended with workspace-scoped child scopes,
/// implementing the 3-tier hierarchy:
///
/// ```
/// AppScope (application lifecycle)
///   └─ ZenithUserScope (account identity, profile, credentials)
///        └─ ZenithWorkspaceScope (tenant DB, outbox, project nodes)
/// ```
///
/// Switching workspaces disposes the [ZenithWorkspaceScope] without logging
/// out the user or destroying the [ZenithUserScope].
class ZenithUserScope extends ZenithTenantScope {
  final Map<String, ZenithTenantScope> _workspaces = {};

  /// Creates a [ZenithUserScope] with [id].
  ZenithUserScope(super.id);

  /// Returns the existing workspace scope for [workspaceId], or creates one.
  ZenithTenantScope getOrCreateWorkspaceScope(String workspaceId) {
    return _workspaces.putIfAbsent(
      workspaceId,
      () => ZenithTenantScope(workspaceId),
    );
  }

  /// Whether a workspace scope for [workspaceId] currently exists.
  bool hasWorkspaceScope(String workspaceId) =>
      _workspaces.containsKey(workspaceId);

  /// Immediately disposes the workspace scope for [workspaceId].
  ///
  /// The [ZenithUserScope] (user identity and credentials) is unaffected.
  void endWorkspaceScope(String workspaceId) {
    final ws = _workspaces.remove(workspaceId);
    ws?.dispose();
  }

  /// Two-phase workspace disposal — awaits drainables with [timeout].
  Future<void> endWorkspaceScopeAsync(
    String workspaceId, {
    Duration timeout = const Duration(milliseconds: 500),
  }) async {
    final ws = _workspaces.remove(workspaceId);
    if (ws != null) {
      await ws.drainAndDispose(timeout: timeout);
    }
  }

  @override
  void dispose({bool purgeZeroize = false}) {
    // Dispose all child workspaces first.
    for (final ws in List.of(_workspaces.values)) {
      ws.dispose(purgeZeroize: purgeZeroize);
    }
    _workspaces.clear();
    super.dispose(purgeZeroize: purgeZeroize);
  }
}
