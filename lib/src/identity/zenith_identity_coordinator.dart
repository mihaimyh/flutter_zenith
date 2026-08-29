import 'package:flutter_zenith/core/zenith/zenith_container.dart';

import '../scope/zenith_scope_manager.dart';
import 'zenith_identity_auth_state.dart';

/// Thrown when an anonymous-to-authenticated migration fails.
///
/// The [ZenithIdentityCoordinator] guarantees that if [ZenithMigrationException]
/// is thrown, the anonymous scope and state are preserved intact.
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

  /// Signs in with a fully authenticated [session] token.
  Future<void> signIn<T>(T session) async {
    final id = session.toString();
    _currentScope = _manager.getOrCreateScope(id);
    _state = AuthAuthenticated<T>(session);
    _notifyListeners();
  }

  /// Signs in as an anonymous guest with [anonId].
  Future<void> signInAnonymously({required String anonId}) async {
    _currentScope = _manager.getOrCreateScope(anonId);
    _state = AuthAnonymous(anonId);
    _notifyListeners();
  }

  /// Signs out: destroys the current scope and resets to [AuthUnauthenticated].
  Future<void> signOut() async {
    final scope = _currentScope;
    _currentScope = null;
    _state = AuthUnauthenticated();
    _notifyListeners();
    if (scope != null) {
      _manager.endScope(scope.id);
    }
  }

  // ─── Anonymous → Authenticated Migration ───────────────────────────────────

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
    required Future<void> Function(
      ZenithContainer fromContainer,
      ZenithContainer toContainer,
    )
    onMigrate,
  }) async {
    final anonScope = _currentScope;
    if (anonScope == null) {
      throw StateError('No current scope to migrate from.');
    }

    final fromId = anonScope.id;
    final toId = newSession.toString();

    _state = AuthMigrating(fromId, toId);

    final toScope = _manager.getOrCreateScope(toId);

    try {
      await onMigrate(anonScope.container, toScope.container);
    } catch (e, st) {
      // Migration failed: tear down the new scope and restore anonymous state.
      _manager.endScope(toId);
      _currentScope = anonScope;
      _state = AuthAnonymous(fromId);
      throw ZenithMigrationException(e, st);
    }

    // Migration succeeded: retire the anonymous scope.
    _manager.endScope(fromId);
    _currentScope = toScope;
    _state = AuthAuthenticated<T>(newSession);
    _notifyListeners();
  }

  // ─── Biometric Fast-Lock ───────────────────────────────────────────────────

  /// Locks the current session for biometric re-authentication.
  ///
  /// The scope and database handles remain open for instant unlock.
  /// [state] transitions to [AuthLocked].
  void lockSession() {
    final scope = _currentScope;
    if (scope == null) return;

    final current = _state;
    Object? session;
    if (current is AuthAuthenticated) {
      session = current.session;
    }

    scope.markDormant();
    _state = AuthLocked(session);
    _notifyListeners();
  }

  /// Unlocks a locked session, restoring the prior authenticated state.
  Future<void> unlockSession() async {
    final scope = _currentScope;
    if (scope == null) return;

    scope.markActive();
    final locked = _state;
    if (locked is AuthLocked) {
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
    if (_manager.hasScope(tenantId)) {
      _manager.endScope(tenantId);
    }
    _currentScope = null;
    _state = AuthUnauthenticated();
    _notifyListeners();

    for (final listener in List.of(_revocationListeners)) {
      try {
        listener(reason);
      } catch (_) {}
    }
  }
}
