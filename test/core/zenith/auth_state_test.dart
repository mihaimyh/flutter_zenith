import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zenith/flutter_zenith.dart';

class TestUser {
  final String id;
  final String email;

  const TestUser({required this.id, required this.email});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TestUser && other.id == id && other.email == email);

  @override
  int get hashCode => Object.hash(id, email);
}

void main() {
  group('AuthState union equality & getters', () {
    const userA = TestUser(id: '1', email: 'alice@example.com');
    const userB = TestUser(id: '2', email: 'bob@example.com');

    test('AuthAuthenticated equality', () {
      expect(
        const AuthAuthenticated<TestUser>(userA),
        equals(const AuthAuthenticated<TestUser>(userA)),
      );
      expect(
        const AuthAuthenticated<TestUser>(userA),
        isNot(equals(const AuthAuthenticated<TestUser>(userB))),
      );
      expect(
        const AuthAuthenticated<TestUser>(userA).hashCode,
        equals(const AuthAuthenticated<TestUser>(userA).hashCode),
      );
    });

    test('AuthUnauthenticated equality', () {
      expect(
        const AuthUnauthenticated<TestUser>(),
        equals(const AuthUnauthenticated<TestUser>()),
      );
    });

    test('AuthAuthenticating equality', () {
      expect(
        const AuthAuthenticating<TestUser>(),
        equals(const AuthAuthenticating<TestUser>()),
      );
    });

    test('AuthError equality', () {
      final err = Exception('Invalid credentials');
      expect(
        AuthError<TestUser>(err, StackTrace.empty),
        equals(AuthError<TestUser>(err, StackTrace.empty)),
      );
    });

    test('boolean status getters', () {
      const AuthState<TestUser> authed = AuthAuthenticated<TestUser>(userA);
      const AuthState<TestUser> unauthed = AuthUnauthenticated<TestUser>();
      const AuthState<TestUser> loading = AuthAuthenticating<TestUser>();
      final AuthState<TestUser> err = AuthError<TestUser>(
        Exception('fail'),
        StackTrace.empty,
      );

      expect(authed.isAuthenticated, isTrue);
      expect(authed.isUnauthenticated, isFalse);
      expect(authed.userOrNull, userA);

      expect(unauthed.isUnauthenticated, isTrue);
      expect(unauthed.isAuthenticated, isFalse);
      expect(unauthed.userOrNull, isNull);

      expect(loading.isAuthenticating, isTrue);
      expect(err.hasError, isTrue);
    });
  });

  group('AuthState pattern matching', () {
    const user = TestUser(id: '1', email: 'alice@example.com');

    test('when exhaustively dispatches to correct branch', () {
      const AuthState<TestUser> state = AuthAuthenticated<TestUser>(user);

      final label = state.when(
        unauthenticated: () => 'logged_out',
        authenticating: () => 'loading',
        authenticated: (u) => 'user:${u.email}',
        error: (err, st) => 'err:$err',
      );

      expect(label, 'user:alice@example.com');
    });

    test('maybeWhen falls back to orElse for unhandled states', () {
      const AuthState<TestUser> state = AuthUnauthenticated<TestUser>();

      final result = state.maybeWhen(
        authenticated: (u) => 'welcome',
        orElse: () => 'login_required',
      );

      expect(result, 'login_required');
    });

    test('whenOrNull returns null for unhandled states', () {
      const AuthState<TestUser> state = AuthAuthenticating<TestUser>();

      final userResult = state.whenOrNull(
        authenticated: (u) => u,
      );

      expect(userResult, isNull);
    });
  });

  group('AuthState with ZenithNode integration', () {
    test('ZenithNode<AuthState<T>> skips duplicate state emissions', () {
      const user = TestUser(id: '1', email: 'alice@example.com');
      final node = ZenithNode<AuthState<TestUser>>(
        const AuthUnauthenticated<TestUser>(),
      );

      var notifications = 0;
      node.subscribe(_CountingSubscriber(() => notifications++));

      // Setting same state produces zero notifications due to equality check
      node.set(const AuthUnauthenticated<TestUser>());
      expect(notifications, 0);

      // Transition to authenticating
      node.set(const AuthAuthenticating<TestUser>());
      expect(notifications, 1);

      // Transition to authenticated
      node.set(const AuthAuthenticated<TestUser>(user));
      expect(notifications, 2);
      expect(node.value.isAuthenticated, isTrue);
    });
  });
}

class _CountingSubscriber implements ZenithSubscriber {
  final void Function() onNotify;
  _CountingSubscriber(this.onNotify);

  @override
  void onNodeChanged(ZenithNode<dynamic> node) => onNotify();
}
