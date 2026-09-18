import 'dart:async';
import '../scope/zenith_scope_manager.dart';

class _CancelledAcquisition extends StateError {
  _CancelledAcquisition() : super('Database acquisition was cancelled');
}

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

/// Owns one connection per tenant. Supply a real driver factory explicitly.
/// Use [InMemoryDatabasePool] for simulated connections in tests.
class ZenithDatabasePool {
  /// Root directory for tenant databases.
  final String baseDir;

  /// Application driver factory for physical database handles.
  final Future<ZenithDatabaseHandle> Function(String path) openHandle;
  final Map<String, ZenithDatabaseHandle> _handles = {};
  final Map<String, Future<ZenithDatabaseHandle>> _pending = {};
  final Map<String, int> _generation = {};
  final Map<ZenithDatabaseHandle, ZenithTenantScope> _owners = {};
  final Map<String, Future<void>> _releasing = {};
  bool _isDisposed = false;
  Future<void>? _disposeFuture;

  /// [openHandle] opens the supplied physical path using the application's driver.
  ZenithDatabasePool({required this.baseDir, required this.openHandle});

  /// Shares in-flight opens and rejects acquisitions for closing scopes.
  Future<ZenithDatabaseHandle> acquireConnection(
    String tenantId, {
    ZenithTenantScope? scope,
  }) async {
    if (_isDisposed) throw StateError('Database pool is disposed');
    if (tenantId.isEmpty) throw ArgumentError.value(tenantId, 'tenantId');
    if (scope != null) {
      if (scope.id != tenantId) {
        throw ArgumentError('Scope and tenant IDs differ');
      }
      if (scope.isDisposed || scope.isClosing) {
        throw StateError('Scope is closing');
      }
    }
    final releasing = _releasing[tenantId];
    if (releasing != null) await releasing;
    if (_isDisposed) throw StateError('Database pool is disposed');
    if (scope != null && (scope.isDisposed || scope.isClosing)) {
      throw StateError('Scope is closing');
    }
    final cached = _handles[tenantId];
    final handle = cached != null && cached.isOpen
        ? cached
        : await (_pending[tenantId] ?? _startOpen(tenantId));
    if (_isDisposed ||
        !handle.isOpen ||
        !identical(_handles[tenantId], handle)) {
      throw StateError('Connection ended before acquisition completed');
    }
    if (scope != null) {
      if (scope.isDisposed || scope.isClosing) {
        if (_owners[handle] == null || identical(_owners[handle], scope)) {
          await _releaseOwned(tenantId, handle);
        }
        throw StateError('Scope ended while opening database');
      }
      bindScope(scope);
    }
    return handle;
  }

  Future<ZenithDatabaseHandle> _startOpen(String tenantId) {
    final generation = _generation[tenantId] ?? 0;
    final completion = Completer<ZenithDatabaseHandle>();
    _pending[tenantId] = completion.future;
    final segment = Uri.encodeComponent(tenantId).replaceAll('.', '%2E');
    Future<ZenithDatabaseHandle>.sync(
          () => openHandle('$baseDir/tenants/$segment/data.db'),
        )
        .then((handle) async {
          if (_isDisposed || generation != (_generation[tenantId] ?? 0)) {
            await handle.close();
            throw _CancelledAcquisition();
          }
          if (!handle.isOpen) {
            throw StateError('Factory returned a closed handle');
          }
          _handles[tenantId] = handle;
          return handle;
        })
        .then(
          (handle) {
            if (identical(_pending[tenantId], completion.future)) {
              _pending.remove(tenantId);
            }
            completion.complete(handle);
          },
          onError: (Object error, StackTrace stack) {
            if (identical(_pending[tenantId], completion.future)) {
              _pending.remove(tenantId);
            }
            completion.completeError(error, stack);
          },
        );
    return completion.future;
  }

  /// Binds the currently open handle, once, to this scope's async cleanup.
  void bindScope(ZenithTenantScope scope) {
    if (scope.isClosing || scope.isDisposed) {
      throw StateError('Scope is closing');
    }
    final handle = _handles[scope.id];
    if (handle == null) throw StateError('Acquire a connection before binding');
    final owner = _owners[handle];
    if (owner != null && !identical(owner, scope)) {
      throw StateError('Connection is still owned by another scope');
    }
    if (owner == null) {
      _owners[handle] = scope;
      scope.onDisposeAsync(() => _releaseOwned(scope.id, handle));
    }
  }

  Future<void> _releaseOwned(
    String tenantId,
    ZenithDatabaseHandle handle,
  ) async {
    if (identical(_handles[tenantId], handle)) {
      await releaseConnection(tenantId);
    }
  }

  /// Closes the cached handle and cancels any in-flight acquisition for this ID.
  Future<void> releaseConnection(String tenantId) {
    final existing = _releasing[tenantId];
    if (existing != null) return existing;
    final completion = Completer<void>();
    _releasing[tenantId] = completion.future;
    _generation[tenantId] = (_generation[tenantId] ?? 0) + 1;
    final pending = _pending.remove(tenantId);
    final handle = _handles.remove(tenantId);
    if (handle != null) _owners.remove(handle);
    Future.wait<void>([
      if (handle != null && handle.isOpen) Future<void>.sync(handle.close),
      if (pending != null) _waitForCancelledOpen(pending),
    ]).then(
      (_) {
        _releasing.remove(tenantId);
        completion.complete();
      },
      onError: (Object error, StackTrace stack) {
        _releasing.remove(tenantId);
        completion.completeError(error, stack);
      },
    );
    return completion.future;
  }

  Future<void> _waitForCancelledOpen(
    Future<ZenithDatabaseHandle> pending,
  ) async {
    try {
      await pending;
    } on _CancelledAcquisition {
      // Cancellation is expected. Driver/open/close failures still propagate.
    }
  }

  /// Permanently closes the pool, including acquisitions already in flight.
  Future<void> disposeAll() {
    if (_disposeFuture != null) return _disposeFuture!;
    _isDisposed = true;
    final ids = {..._handles.keys, ..._pending.keys, ..._releasing.keys};
    return _disposeFuture = Future.wait(
      ids.map(releaseConnection),
    ).then((_) {});
  }
}

/// Simulated connections for tests; never touches physical storage.
class InMemoryDatabasePool extends ZenithDatabasePool {
  /// Creates an in-memory pool rooted at [baseDir].
  InMemoryDatabasePool({required super.baseDir})
    : super(openHandle: (path) async => _InMemoryHandle(path));
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
