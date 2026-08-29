/// Extended authentication state hierarchy for the `zenith_identity` layer.
///
/// This sealed hierarchy is distinct from the existing `AuthState<T>` in
/// `flutter_zenith` — it models the additional mobile-specific states needed
/// for anonymous account linking, biometric fast-lock, and dual-container
/// migration pipelines.
///
/// States:
/// - [AuthUnauthenticated] — no active session.
/// - [AuthAnonymous] — guest session with a temporary [anonId].
/// - [AuthAuthenticated] — fully signed-in with a [session] token.
/// - [AuthMigrating] — transitioning from anonymous to authenticated.
/// - [AuthLocked] — session paused for biometric re-authentication.
sealed class ZenithAuthState {}

/// No active session. The user has signed out or never signed in.
final class AuthUnauthenticated extends ZenithAuthState {
  @override
  String toString() => 'AuthUnauthenticated()';
}

/// A guest/anonymous session identified by [anonId].
///
/// The user may upgrade to a full [AuthAuthenticated] state via
/// [ZenithIdentityCoordinator.upgradeAnonymousAccount].
final class AuthAnonymous extends ZenithAuthState {
  /// The temporary anonymous identifier assigned by the backend.
  final String anonId;

  /// Creates an [AuthAnonymous] state with [anonId].
  AuthAnonymous(this.anonId);

  @override
  String toString() => 'AuthAnonymous($anonId)';
}

/// A fully authenticated session carrying [session] data of type [T].
final class AuthAuthenticated<T> extends ZenithAuthState {
  /// The session token / user object for this authenticated session.
  final T session;

  /// Creates an [AuthAuthenticated] state with [session].
  AuthAuthenticated(this.session);

  @override
  String toString() => 'AuthAuthenticated($session)';
}

/// A transitional state while migrating data from an anonymous container
/// ([fromId]) to an authenticated container ([toId]).
final class AuthMigrating extends ZenithAuthState {
  /// The anonymous scope id being retired.
  final String fromId;

  /// The authenticated scope id being initialised.
  final String toId;

  /// Creates an [AuthMigrating] state.
  AuthMigrating(this.fromId, this.toId);

  @override
  String toString() => 'AuthMigrating($fromId → $toId)';
}

/// The session is biometric-locked. The underlying scope and database handles
/// remain open for instant unlock; UI mutations are paused.
final class AuthLocked<T> extends ZenithAuthState {
  /// The session data preserved during the lock.
  final T session;

  /// Creates an [AuthLocked] state with [session].
  AuthLocked(this.session);

  @override
  String toString() => 'AuthLocked($session)';
}
