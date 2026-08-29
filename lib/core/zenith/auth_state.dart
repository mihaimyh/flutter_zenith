import 'package:flutter/foundation.dart';

/// A sealed union representing authentication lifecycle states.
///
/// Models all standard auth transitions:
/// - [AuthUnauthenticated] — no active user session.
/// - [AuthAuthenticating] — login / authentication request in progress.
/// - [AuthAuthenticated] — successfully authenticated with user object [user].
/// - [AuthError] — authentication attempt failed with [error] and [stackTrace].
///
/// Useful for routing guards (e.g. GoRouter / AutoRoute) and user session management:
/// ```dart
/// final authNode = ZenithNode<AuthState<User>>(const AuthUnauthenticated());
///
/// String get initialRoute => authNode.value.when(
///   authenticated: (user) => '/home',
///   unauthenticated: () => '/login',
///   authenticating: () => '/splash',
///   error: (_, __) => '/login',
/// );
/// ```
@immutable
sealed class AuthState<T> {
  /// Creates an [AuthState].
  const AuthState();

  /// Exhaustively pattern-matches all four auth states.
  R when<R>({
    required R Function() unauthenticated,
    required R Function() authenticating,
    required R Function(T user) authenticated,
    required R Function(Object error, StackTrace stackTrace) error,
  }) {
    final onUnauth = unauthenticated;
    final onAuthng = authenticating;
    final onAuthed = authenticated;
    final onError = error;

    return switch (this) {
      AuthUnauthenticated<T>() => onUnauth(),
      AuthAuthenticating<T>() => onAuthng(),
      AuthAuthenticated<T>(:final user) => onAuthed(user),
      AuthError<T>(:final error, :final stackTrace) => onError(
        error,
        stackTrace,
      ),
    };
  }

  /// Pattern-matches with an [orElse] fallback for unhandled states.
  R maybeWhen<R>({
    R Function()? unauthenticated,
    R Function()? authenticating,
    R Function(T user)? authenticated,
    R Function(Object error, StackTrace stackTrace)? error,
    required R Function() orElse,
  }) {
    return switch (this) {
      AuthUnauthenticated<T>() =>
        unauthenticated != null ? unauthenticated() : orElse(),
      AuthAuthenticating<T>() =>
        authenticating != null ? authenticating() : orElse(),
      AuthAuthenticated<T>(:final user) =>
        authenticated != null ? authenticated(user) : orElse(),
      AuthError<T>(error: final err, stackTrace: final st) =>
        error != null ? error(err, st) : orElse(),
    };
  }

  /// Pattern-matches and returns `null` for unhandled states.
  R? whenOrNull<R>({
    R Function()? unauthenticated,
    R Function()? authenticating,
    R Function(T user)? authenticated,
    R Function(Object error, StackTrace stackTrace)? error,
  }) {
    return switch (this) {
      AuthUnauthenticated<T>() => unauthenticated?.call(),
      AuthAuthenticating<T>() => authenticating?.call(),
      AuthAuthenticated<T>(:final user) => authenticated?.call(user),
      AuthError<T>(error: final err, stackTrace: final st) =>
        error?.call(err, st),
    };
  }

  /// The active user object if authenticated, or `null` otherwise.
  T? get userOrNull => switch (this) {
    AuthAuthenticated<T>(:final user) => user,
    _ => null,
  };

  /// Whether a user is currently authenticated.
  bool get isAuthenticated => this is AuthAuthenticated<T>;

  /// Whether the user is currently unauthenticated.
  bool get isUnauthenticated => this is AuthUnauthenticated<T>;

  /// Whether an authentication request is in progress.
  bool get isAuthenticating => this is AuthAuthenticating<T>;

  /// Whether an authentication error has occurred.
  bool get hasError => this is AuthError<T>;
}

/// State representing an unauthenticated / logged-out session.
class AuthUnauthenticated<T> extends AuthState<T> {
  /// Creates an [AuthUnauthenticated] state.
  const AuthUnauthenticated();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is AuthUnauthenticated<T>;

  @override
  int get hashCode => Object.hash(runtimeType, T);

  @override
  String toString() => 'AuthUnauthenticated<$T>()';
}

/// State representing an active login or token verification in progress.
class AuthAuthenticating<T> extends AuthState<T> {
  /// Creates an [AuthAuthenticating] state.
  const AuthAuthenticating();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is AuthAuthenticating<T>;

  @override
  int get hashCode => Object.hash(runtimeType, T);

  @override
  String toString() => 'AuthAuthenticating<$T>()';
}

/// State representing a successfully authenticated session with [user] data.
class AuthAuthenticated<T> extends AuthState<T> {
  /// The authenticated user data object.
  final T user;

  /// Creates an [AuthAuthenticated] state with [user].
  const AuthAuthenticated(this.user);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AuthAuthenticated<T> && other.user == user);

  @override
  int get hashCode => Object.hash(runtimeType, user);

  @override
  String toString() => 'AuthAuthenticated<$T>($user)';
}

/// State representing a failed authentication attempt with [error].
class AuthError<T> extends AuthState<T> {
  /// The error object describing the failure.
  final Object error;

  /// The stack trace captured during the failure.
  final StackTrace stackTrace;

  /// Creates an [AuthError] state with [error] and [stackTrace].
  const AuthError(this.error, this.stackTrace);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AuthError<T> && other.error == error);

  @override
  int get hashCode => Object.hash(runtimeType, error);

  @override
  String toString() => 'AuthError<$T>($error)';
}
