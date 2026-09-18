import 'dart:async';

import 'package:flutter_zenith/core/zenith/zenith_container.dart';
import 'package:flutter_zenith/core/zenith/zenith_key.dart';
import 'package:flutter_zenith/core/zenith/zenith_node.dart';

import '../enterprise/zenith_secure_bytes.dart';
import 'zenith_drainable.dart';
import 'zenith_ipc.dart';
import 'zenith_user_scope.dart';

export 'package:flutter_zenith/core/zenith/zenith_container.dart'
    show ZenithCaptiveDependencyException;

/// The scope lifetime tier used by the Captive Dependency Guard to detect
/// when a longer-lived container holds a direct reference to a shorter-lived one.
enum ZenithLifetime {
  /// Application-wide singleton — lives as long as the app.
  singleton,

  /// Tenant/user-scoped — disposed when the user logs out or the scope ends.
  scoped,
}

/// A named, isolated container scope managed by [ZenithScopeManager].
///
/// Each tenant (user account, anonymous session, background worker) gets its
/// own [ZenithTenantScope] so nodes cannot leak across tenants. The scope:
/// - Wraps a private [ZenithContainer].
/// - Tracks in-flight cancellation tokens and cancels them on disposal.
/// - Supports two-phase teardown via [ZenithDrainable] registration.
/// - Can be made [isDormant] (biometric lock) while keeping DB handles open.
class ZenithTenantScope {
  /// The stable identifier for this scope (e.g. a user-id or 'anon_123').
  final String id;

  /// The isolated dependency container for this scope.
  final ZenithContainer container;

  /// Tracks which keys were registered as [ZenithLifetime.scoped] so the
  /// Captive Dependency Guard can detect violations.
  final Set<Object> _scopedKeys = {};

  final List<ZenithDrainable> _drainables = [];
  final List<void Function()> _disposeCallbacks = [];
  final List<ZenithCancellationToken> _activeTokens = [];
  IpcListenerEntry? _ipcListener;

  bool _isDisposed = false;
  bool _isClosing = false;
  Future<void>? _drainFuture;
  Future<void> _disposalComplete = Future.value();
  final List<Future<void> Function()> _asyncDisposeCallbacks = [];

  /// Whether teardown has begun. New scoped work is rejected while closing.
  bool get isClosing => _isClosing;

  /// Completion and errors of asynchronous cleanup started by [dispose].
  Future<void> get disposalComplete => _disposalComplete;

  /// Registers resource cleanup that [drainAndDispose] will await.
  /// After disposal, await the returned [disposalComplete] for cleanup errors.
  void onDisposeAsync(Future<void> Function() callback) {
    if (_isDisposed) throw StateError('Scope is disposed');
    _asyncDisposeCallbacks.add(callback);
  }

  bool _isDormant = false;

  /// Creates a [ZenithTenantScope] with [id] and a fresh [ZenithContainer].
  ZenithTenantScope(this.id)
    : container = ZenithContainer(isScopedContainer: id != '__app__');

  /// Whether this scope has been disposed.
  bool get isDisposed => _isDisposed;

  /// Whether this scope is dormant (biometric lock active).
  ///
  /// Dormancy is an identity/UI signal, not a lock on direct node writes.
  /// The container stays open so background state can remain current.
  bool get isDormant => _isDormant;

  /// Puts this scope into dormant (biometric-locked) state.
  void markDormant() => _isDormant = true;

  /// Restores this scope from dormant state.
  void markActive() => _isDormant = false;

  /// Registers [drainable] to be awaited during two-phase scope teardown.
  void registerDrainable(ZenithDrainable drainable) {
    if (_isDisposed || _isClosing) throw StateError('Scope is closing');
    _drainables.add(drainable);
  }

  /// Registers [callback] to be invoked when this scope is disposed.
  void onDispose(void Function() callback) {
    if (_isDisposed) {
      callback();
      return;
    }
    _disposeCallbacks.add(callback);
  }

  /// Registers [key] with a [factory] in the container, tagging it with
  /// [lifetime] for Captive Dependency Guard enforcement.
  ///
  /// If [lifetime] is [ZenithLifetime.singleton], the factory must **not**
  /// try to resolve any [ZenithLifetime.scoped] key from this container —
  /// doing so throws [ZenithCaptiveDependencyException] immediately.
  void register<T>(
    ZenithKey<T> key,
    T Function() factory, {
    ZenithLifetime lifetime = ZenithLifetime.scoped,
  }) {
    if (_isDisposed || _isClosing) {
      throw StateError('Cannot register in a disposed ZenithTenantScope');
    }

    if (lifetime == ZenithLifetime.scoped) {
      _scopedKeys.add(key);
      container.getOrCreate<T>(key, (_) => factory());
    } else {
      // Singleton registration: wrap factory to detect captive dependencies.
      container.getOrCreate<T>(key, (_) {
        return _CaptiveGuard.runSingleton(factory);
      });
    }
  }

  /// Resolves the value for [key] from this scope's container.
  T resolve<T>(ZenithKey<T> key) {
    final node = container.maybeNode<T>(key);
    if (node == null) {
      throw StateError('Key $key not found in scope "$id"');
    }
    return node.value;
  }

  /// Returns the node for [key] if registered, or null.
  ZenithNode<T>? maybeNode<T>(ZenithKey<T> key) {
    return container.maybeNode<T>(key);
  }

  /// Runs [task] guarded so that scope disposal automatically cancels it.
  ///
  /// A [ZenithCancellationToken] is created and linked; if [dispose] is called
  /// before [task] completes, the token is cancelled, stopping any registered
  /// `onCancel` callbacks (e.g. aborting HTTP requests).
  void runGuarded(Future<void> Function() task) {
    if (_isDisposed || _isClosing) return;

    final token = ZenithCancellationToken();
    _activeTokens.add(token);

    task()
        .then((_) {
          _activeTokens.remove(token);
        })
        .catchError((error, stackTrace) {
          _activeTokens.remove(token);
          Error.throwWithStackTrace(error, stackTrace);
        });
  }

  /// Runs [task] providing a [ZenithCancellationToken] that is cancelled when
  /// this scope is disposed.
  void runWithToken(Future<void> Function(ZenithCancellationToken token) task) {
    if (_isDisposed || _isClosing) return;

    final token = ZenithCancellationToken();
    _activeTokens.add(token);

    task(token)
        .then((_) {
          _activeTokens.remove(token);
        })
        .catchError((error, stackTrace) {
          _activeTokens.remove(token);
          Error.throwWithStackTrace(error, stackTrace);
        });
  }

  /// Listens for [ZenithInvalidateMessage]s on an IsolateNameServer port.
  ///
  /// When a message arrives with this scope's [id] as the tenant, [onInvalidate]
  /// is called with the node key string.
  void listenToInterIsolateInvalidations(
    String portName, {
    required void Function(String key) onInvalidate,
  }) {
    _ipcListener?.cancel();
    _ipcListener = IpcListenerEntry(portName, id, onInvalidate);
  }

  /// Immediately disposes this scope: cancels tokens, fires dispose callbacks,
  /// optionally zeroizes [Zeroizable] nodes, then disposes the container.
  void dispose({bool purgeZeroize = false}) {
    if (_isDisposed) return;
    _isDisposed = true;
    _isClosing = true;

    // Cancel all in-flight guarded tasks.
    for (final token in List.of(_activeTokens)) {
      token.cancel();
    }
    _activeTokens.clear();

    // Fire dispose callbacks.
    for (final cb in List.of(_disposeCallbacks)) {
      try {
        cb();
      } catch (_) {}
    }
    _disposeCallbacks.clear();

    // Stop IPC listener.
    _ipcListener?.cancel();
    _ipcListener = null;

    // Dispose the container (and zeroize secure nodes if requested).
    container.dispose(purgeZeroize: purgeZeroize);
    _drainables.clear();
    final cleanup = List.of(_asyncDisposeCallbacks);
    _asyncDisposeCallbacks.clear();
    _disposalComplete = Future.wait([
      container.disposalComplete,
      ...cleanup.map((cb) => Future<void>.sync(cb)),
    ]).then((_) {});
    // Synchronous dispose is best-effort; callers can await disposalComplete.
    _disposalComplete.ignore();
  }

  /// Awaits all registered [ZenithDrainable]s then calls [dispose].
  Future<void> drainAndDispose({
    Duration timeout = const Duration(milliseconds: 500),
    bool purgeZeroize = false,
  }) {
    if (_drainFuture != null) return _drainFuture!;
    if (_isDisposed) return _disposalComplete;
    _isClosing = true;
    final completion = Completer<void>();
    _drainFuture = completion.future;
    _drain(
      timeout,
      purgeZeroize,
    ).then(completion.complete, onError: completion.completeError);
    return completion.future;
  }

  /// Override to drain currently owned child scopes before disposal.
  Future<void> drainOwnedScopes({
    required Duration timeout,
    required bool purgeZeroize,
  }) async {}

  Future<void> _drain(Duration timeout, bool purgeZeroize) async {
    Object? failure;
    StackTrace? failureStack;
    try {
      await Future.wait([
        ...List.of(_drainables).map((d) => Future<void>.sync(d.drain)),
        Future<void>.sync(
          () => drainOwnedScopes(timeout: timeout, purgeZeroize: purgeZeroize),
        ),
      ]).timeout(timeout, onTimeout: () => []);
    } catch (error, stack) {
      failure = error;
      failureStack = stack;
    } finally {
      dispose(purgeZeroize: purgeZeroize);
      try {
        await _disposalComplete;
      } catch (error, stack) {
        failure ??= error;
        failureStack ??= stack;
      }
    }
    if (failure != null) Error.throwWithStackTrace(failure, failureStack!);
  }
}

/// Internal helper for captive dependency detection.
class _CaptiveGuard {
  static T runSingleton<T>(T Function() factory) {
    return runZoned(
      factory,
      zoneValues: {#zenith_is_singleton_construction: true},
    );
  }
}

/// A one-shot cancellation signal passed to async tasks so they can abort
/// in-flight work (HTTP calls, DB operations) when the owning scope ends.
///
/// ```dart
/// userScope.runWithToken((token) async {
///   token.onCancel(() => httpClient.close());
///   final data = await httpClient.get('/api/data');
///   if (token.isCancelled) return;
///   stateNode.value = data;
/// });
/// ```
class ZenithCancellationToken {
  bool _isCancelled = false;
  final List<void Function()> _callbacks = [];

  /// Whether this token has been cancelled.
  bool get isCancelled => _isCancelled;

  /// Registers [callback] to run synchronously when this token is cancelled.
  ///
  /// If already cancelled, [callback] is invoked immediately.
  void onCancel(void Function() callback) {
    if (_isCancelled) {
      callback();
      return;
    }
    _callbacks.add(callback);
  }

  /// Cancels this token, invoking all registered [onCancel] callbacks.
  ///
  /// Idempotent — cancelling an already-cancelled token is a no-op.
  void cancel() {
    if (_isCancelled) return;
    _isCancelled = true;
    for (final cb in List.of(_callbacks)) {
      try {
        cb();
      } catch (_) {}
    }
    _callbacks.clear();
  }
}

/// Manages the root application scope and all tenant child scopes.
///
/// ```dart
/// final manager = ZenithScopeManager();
/// final userScope = manager.getOrCreateScope('user_123');
/// manager.endScope('user_123');
/// ```
class ZenithScopeManager {
  /// The root application-level scope (singleton lifetime).
  final ZenithTenantScope appScope = ZenithTenantScope('__app__');

  final Map<String, ZenithTenantScope> _scopes = {};
  final Map<String, Future<void>> _ending = {};

  /// Returns whether a scope with [id] is currently active.
  bool hasScope(String id) => _scopes.containsKey(id);

  /// Returns the existing scope for [id], or creates a new [ZenithTenantScope].
  ZenithTenantScope getOrCreateScope(String id) {
    return _scopes.putIfAbsent(id, () => ZenithTenantScope(id));
  }

  /// Returns the existing [ZenithUserScope] for [id], or creates one.
  ZenithUserScope getOrCreateUserScope(String id) {
    if (_scopes.containsKey(id)) {
      final existing = _scopes[id]!;
      if (existing is ZenithUserScope) return existing;
      // Dispose the existing base scope to prevent a memory leak before replacing it
      existing.dispose();
    }
    final scope = ZenithUserScope(id);
    _scopes[id] = scope;
    return scope;
  }

  /// Immediately disposes the scope for [id] and removes it from the registry.
  void endScope(String id, {bool purgeZeroize = false}) {
    final scope = _scopes.remove(id);
    scope?.dispose(purgeZeroize: purgeZeroize);
  }

  /// Two-phase scope teardown: awaits registered drainables with [timeout]
  /// before disposing the scope.
  Future<void> endScopeAsync(
    String id, {
    Duration timeout = const Duration(milliseconds: 500),
    bool purgeZeroize = false,
  }) async {
    final scope = _scopes.remove(id);
    if (scope == null) {
      await _ending[id];
      return;
    }
    final ending = scope.drainAndDispose(
      timeout: timeout,
      purgeZeroize: purgeZeroize,
    );
    _ending[id] = ending;
    try {
      await ending;
    } finally {
      if (identical(_ending[id], ending)) _ending.remove(id);
    }
  }

  /// Creates a minimal headless [ZenithTenantScope] for background isolates
  /// or Workmanager tasks — does not require Flutter bindings.
  static Future<ZenithTenantScope> bootstrapHeadless({
    required String tenantId,
    Object? Function(String tenantId)? storageFactory,
  }) async {
    final scope = ZenithTenantScope(tenantId);
    if (storageFactory != null) {
      final storage = storageFactory(tenantId);
      if (storage != null) {
        scope.container.getOrCreate(
          ZenithKey<Object>('__headless_storage__'),
          (_) => storage,
        );
      }
    }
    return scope;
  }
}
