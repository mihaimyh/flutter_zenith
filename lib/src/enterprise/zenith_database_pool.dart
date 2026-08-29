import '../scope/zenith_drainable.dart';
import '../scope/zenith_scope_manager.dart';

/// Abstract handle to a single database connection for one tenant.
///
/// Concrete implementations wire this to SQLite (via `sqflite` or `drift`),
/// an in-memory store for tests, or any other persistence engine.
abstract class ZenithDatabaseHandle {
  /// The absolute path of the physical database file.
  ///
  /// For in-memory handles, this is a synthetic path used for test assertions.
  String get filePath;

  /// Whether the database connection is currently open.
  bool get isOpen;

  /// Closes the database connection and releases file locks.
  ///
  /// Idempotent — calling [close] on an already-closed handle is a no-op.
  Future<void> close();
}

/// Provisions and tracks per-tenant [ZenithDatabaseHandle]s, isolating each
/// tenant's data to a separate physical file.
///
/// File path convention: `{baseDir}/tenants/{tenantId}/data.db`
///
/// ```dart
/// final pool = ZenithDatabasePool(baseDir: '/app/db');
/// final handle = await pool.acquireConnection('user_a', scope: userAScope);
/// // handle.filePath == '/app/db/tenants/user_a/data.db'
/// ```
class ZenithDatabasePool {
  /// The base directory under which tenant sub-directories are created.
  final String baseDir;

  final Map<String, ZenithDatabaseHandle> _handles = {};

  /// Creates a [ZenithDatabasePool] rooted at [baseDir].
  ZenithDatabasePool({required this.baseDir});

  /// Opens (or returns the cached open) handle for [tenantId].
  ///
  /// If [scope] is provided, this database pool automatically attaches a
  /// [ZenithDrainable] to [scope] so that [releaseConnection] is called
  /// automatically when the scope drains or disposes.
  Future<ZenithDatabaseHandle> acquireConnection(
    String tenantId, {
    ZenithTenantScope? scope,
  }) async {
    final existing = _handles[tenantId];
    if (existing != null && existing.isOpen) {
      if (scope != null) {
        bindScope(scope);
      }
      return existing;
    }
    final path = '$baseDir/tenants/$tenantId/data.db';
    final handle = await _openHandle(path);
    _handles[tenantId] = handle;

    if (scope != null) {
      bindScope(scope);
    }
    return handle;
  }

  /// Automatically binds this pool's connection release to [scope]'s
  /// drainable lifecycle, ensuring physical file locks are released on logout.
  void bindScope(ZenithTenantScope scope) {
    scope.registerDrainable(
      ZenithDrainableCallback(() => releaseConnection(scope.id)),
    );
  }

  /// Closes the connection for [tenantId] if it is open.
  Future<void> releaseConnection(String tenantId) async {
    final handle = _handles.remove(tenantId);
    if (handle != null && handle.isOpen) {
      await handle.close();
    }
  }

  /// Closes all open connections.
  Future<void> disposeAll() async {
    for (final handle in List.of(_handles.values)) {
      if (handle.isOpen) {
        await handle.close();
      }
    }
    _handles.clear();
  }

  /// Factory method — override in subclasses or provide [InMemoryDatabasePool]
  /// for tests. Default implementation returns an [_InMemoryHandle].
  Future<ZenithDatabaseHandle> _openHandle(String path) async {
    return _InMemoryHandle(path);
  }
}

/// An in-memory [ZenithDatabasePool] for unit tests.
///
/// Returns [InMemoryDatabaseHandle]s that simulate file-path isolation without
/// touching disk. No SQLite or platform dependencies required.
class InMemoryDatabasePool extends ZenithDatabasePool {
  /// Creates an [InMemoryDatabasePool] with [baseDir].
  InMemoryDatabasePool({required super.baseDir});

  @override
  Future<ZenithDatabaseHandle> _openHandle(String path) async {
    return _InMemoryHandle(path);
  }
}

/// Internal in-memory implementation of [ZenithDatabaseHandle].
class _InMemoryHandle implements ZenithDatabaseHandle {
  @override
  final String filePath;

  bool _isOpen = true;

  _InMemoryHandle(this.filePath);

  @override
  bool get isOpen => _isOpen;

  @override
  Future<void> close() async {
    _isOpen = false;
  }
}
