import 'zenith_authorization_service.dart';
import 'zenith_policy.dart';
import 'zenith_requirement.dart';

/// Evaluates a [ZenithPolicy] synchronously at the navigation layer, returning
/// a redirect path if access is denied.
///
/// Designed for use with declarative routers (`go_router`, `auto_route`):
///
/// ```dart
/// final redirect = ZenithRouteGuard.evaluate(
///   context: userSecurityContext,
///   policy: adminPolicy,
///   authService: authService,
///   deniedRedirectPath: '/login',
/// );
/// if (redirect != null) return redirect;
/// ```
class ZenithRouteGuard {
  ZenithRouteGuard._();

  /// Evaluates [policy] against [context] via [authService].
  ///
  /// Returns `null` if access is granted, or [deniedRedirectPath] if denied.
  static String? evaluate({
    required UserSecurityContext context,
    required ZenithPolicy policy,
    required ZenithAuthorizationService authService,
    required String deniedRedirectPath,
  }) {
    final result = authService.evaluate(context, policy);
    return result.isAuthorized ? null : deniedRedirectPath;
  }
}
