import 'package:flutter_zenith/core/zenith/zenith_container.dart';

import '../scope/zenith_scope_manager.dart';
import 'zenith_identity_auth_state.dart';

/// Thrown when an anonymous-to-authenticated migration fails.
///
/// The [ZenithIdentityCoordinator] guarantees that if [ZenithMigrationException]
/// is thrown, the anonymous state is restored unless a newer identity
/// transition has superseded the migration.
class ZenithMigrationException implements Exception {
  /// The underlying cause of the migration failure.
  final Object cause;

  /// The stack trace at the point of failure.
  final StackTrace stackTrace;

  /// Creates a [ZenithMigrationException] with [cause] and [stackTrace].
  ZenithMigrationException(this.cause, this.stackTrace);

  @override
  String toString() => 'ZenithMigrationException: $cause';
}

/// Reasons a remote authority may revoke a session.
enum RevocationReason {
  /// An administrator forcibly invalidated the session.
  sessionInvalidatedByAdmin,

  /// The session token expired on the server.
  tokenExpired,

  /// A security violation was detected (e.g. concurrent login from another device).
  securityViolation,
}

/// Coordinates the full identity lifecycle for a mobile application.
///
/// Manages authentication state transitions, anonymous account linking,
/// biometric fast-lock, and back-channel revocation. Internally owns a
/// [ZenithScopeManager] so that each identity has a fully isolated container.
///
/// ```dart
/// final coordinator = ZenithIdentityCoordinator();
/// await coordinator.signInAnonymously(anonId: 'anon_123');
/// await coordinator.upgradeAnonymousAccount(
///   newSession: 'user_456',
///   onMigrate: (from, to) async { /* copy cart, etc. */ },
/// );
/// ```
class ZenithIdentityCoordinator {
  final ZenithScopeManager _manager = ZenithScopeManager();

  ZenithAuthState _state = AuthUnauthenticated();
  ZenithTenantScope? _currentScope;
  ZenithTenantScope? _migrationScope;
  int _generation = 0;
  Future<void>? _signOutFuture;

  String _identity(Object? session, String? tenantId) {
    final id = tenantId ?? (session is String ? session : null);
    if (id == null || id.isEmpty) {
      throw ArgumentError('Provide a non-empty tenantId for object sessions.');
    }
    return id;
  }

  Future<void> _cancelMigration() {
    final pending = _migrationScope;
    _migrationScope = null;
    return pending == null
        ? Future.value()
        : _manager.endScopeAsync(pending.id);
  }

  final List<void Function(RevocationReason reason)> _revocationListeners = [];
  final List<void Function()> _listeners = [];

  /// Registers a callback to be notified when the authentication state changes.
  void addListener(void Function() listener) {
    _listeners.add(listener);
  }

  /// Unregisters a previously registered callback.
  void removeListener(void Function() listener) {
    _listeners.remove(listener);
  }

  void _notifyListeners() {
    for (final listener in List.of(_listeners)) {
      try {
        listener();
      } catch (_) {}
    }
  }

  /// The current authentication state.
  ZenithAuthState get state => _state;

  /// The currently active [ZenithTenantScope], or `null` if unauthenticated.
  ZenithTenantScope? get currentScope => _currentScope;

  /// Returns whether a scope with [id] exists in the internal scope manager.
  bool hasScope(String id) => _manager.hasScope(id);

  // ─── Authentication Transitions ────────────────────────────────────────────

  /// Signs in using an explicit stable tenant ID. String sessions may be used
  /// directly as IDs for compatibility; objects must supply [tenantId].
  Future<void> signIn<T>(T session, {String? tenantId}) async {
    final id = _identity(session, tenantId);
    _generation++;
    final cleanup = _cancelMigration();
    final old = _currentScope;
    final retirement = old != null && old.id != id
        ? _manager.endScopeAsync(old.id)
        : Future<void>.value();
    _currentScope = _manager.getOrCreateScope(id);
    _currentScope!.markActive();
    _state = AuthAuthenticated<T>(session);
    _notifyListeners();
    await Future.wait([cleanup, retirement]);
  }

  /// Signs in as an anonymous guest and retires the prior identity.
  Future<void> signInAnonymously({required String anonId}) async {
    _identity(anonId, null);
    _generation++;
    final cleanup = _cancelMigration();
    final old = _currentScope;
    final retirement = old != null && old.id != anonId
        ? _manager.endScopeAsync(old.id)
        : Future<void>.value();
    _currentScope = _manager.getOrCreateScope(anonId);
    _currentScope!.markActive();
    _state = AuthAnonymous(anonId);
    _notifyListeners();
    await Future.wait([cleanup, retirement]);
  }

  /// Clears identity immediately and awaits pending resource teardown.
  Future<void> signOut() async {
    if (_currentScope == null &&
        _migrationScope == null &&
        _signOutFuture != null) {
      await _signOutFuture;
      return;
    }
    _generation++;
    final cleanup = _cancelMigration();
    final scope = _currentScope;
    _currentScope = null;
    _state = AuthUnauthenticated();
    final retirement = scope == null
        ? Future<void>.value()
        : _manager.endScopeAsync(scope.id);
    final completion = Future.wait([cleanup, retirement]).then<void>((_) {});
    _signOutFuture = completion;
    _notifyListeners();
    try {
      await completion;
    } finally {
      if (identical(_signOutFuture, completion)) _signOutFuture = null;
    }
  }

  /// Upgrades an anonymous session to a fully authenticated one.
  ///
  /// [onMigrate] receives both containers concurrently: read from [fromContainer]
  /// (retiring anonymous scope) and write to [toContainer] (incoming authenticated
  /// scope). If [onMigrate] throws, the anonymous scope is preserved and a
  /// [ZenithMigrationException] is rethrown.
  ///
  /// On success: the anonymous scope is destroyed and [state] transitions to
  /// [AuthAuthenticated].
  Future<void> upgradeAnonymousAccount<T>({
    required T newSession,
    String? tenantId,
    required Future<void> Function(
      ZenithContainer fromContainer,
      ZenithContainer toContainer,
    )
    onMigrate,
  }) async {
    final anonScope = _currentScope;
    if (anonScope == null || _state is! AuthAnonymous) {
      throw StateError('Migration requires an anonymous session.');
    }
    final fromId = anonScope.id;
    final toId = _identity(newSession, tenantId);
    if (toId == fromId || _manager.hasScope(toId)) {
      throw ArgumentError('Migration requires a distinct, unused tenant ID.');
    }
    final generation = ++_generation;
    final toScope = _manager.getOrCreateScope(toId);
    _migrationScope = toScope;
    _state = AuthMigrating(fromId, toId);
    _notifyListeners();
    if (generation != _generation) return;
    try {
      await onMigrate(anonScope.container, toScope.container);
    } catch (error, stack) {
      if (generation == _generation) {
        _migrationScope = null;
        final cleanup = _manager.endScopeAsync(toId);
        _state = AuthAnonymous(fromId);
        _notifyListeners();
        // Cleanup must not replace the original migration error.
        try {
          await cleanup;
        } catch (_) {}
      }
      throw ZenithMigrationException(error, stack);
    }
    if (generation != _generation) return;
    _migrationScope = null;
    final cleanup = _manager.endScopeAsync(fromId);
    _currentScope = toScope;
    _state = AuthAuthenticated<T>(newSession);
    _notifyListeners();
    await cleanup;
  }

  /// Locks the current session for biometric re-authentication.
  ///
  /// The scope and database handles remain open for instant unlock.
  /// [state] transitions to [AuthLocked].
  void lockSession() {
    final scope = _currentScope;
    if (scope == null) return;

    final current = _state;
    if (current is! AuthAuthenticated) return;
    final session = current.session;

    scope.markDormant();
    _state = AuthLocked(session);
    _notifyListeners();
  }

  /// Unlocks a locked session, restoring the prior authenticated state.
  Future<void> unlockSession() async {
    final scope = _currentScope;
    if (scope == null) return;

    final locked = _state;
    if (locked is AuthLocked) {
      scope.markActive();
      _state = AuthAuthenticated(locked.session);
      _notifyListeners();
    }
  }

  // ─── Back-Channel Revocation ───────────────────────────────────────────────

  /// Registers [listener] to be called when a remote revocation is received.
  void onSecurityRevocation(void Function(RevocationReason reason) listener) {
    _revocationListeners.add(listener);
  }

  /// Ingests a remote revocation signal for [tenantId], terminating the
  /// session and notifying all registered revocation listeners.
  Future<void> ingestRemoteRevocation({
    required String tenantId,
    required RevocationReason reason,
  }) async {
    if (_currentScope?.id == tenantId || _migrationScope?.id == tenantId) {
      await signOut();
    } else {
      await _manager.endScopeAsync(tenantId);
    }

    for (final listener in List.of(_revocationListeners)) {
      try {
        listener(reason);
      } catch (_) {}
    }
  }
}
