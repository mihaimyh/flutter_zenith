import 'zenith_policy.dart';
import 'zenith_requirement.dart';

/// The result of evaluating a [ZenithPolicy] against a [UserSecurityContext].
class AuthorizationResult {
  /// Whether the policy grants access.
  final bool isAuthorized;

  /// Human-readable reason for the decision (populated on denial).
  final String? reason;

  /// Creates an [AuthorizationResult].
  const AuthorizationResult({required this.isAuthorized, this.reason});

  @override
  String toString() => 'AuthorizationResult(isAuthorized: $isAuthorized'
      '${reason != null ? ", reason: $reason" : ""})';
}

/// Evaluates [ZenithPolicy] instances against [UserSecurityContext]s.
///
/// ```dart
/// final service = ZenithAuthorizationService();
/// final result = service.evaluate(userContext, exportPolicy);
/// if (result.isAuthorized) { /* proceed */ }
/// ```
class ZenithAuthorizationService {
  /// Creates a [ZenithAuthorizationService].
  const ZenithAuthorizationService();

  /// Evaluates [policy] against [context], returning an [AuthorizationResult].
  ///
  /// Evaluation order:
  /// 1. If [policy.requirements] is provided, all must return `true`.
  /// 2. If [policy.evaluate] is provided, it must return `true`.
  /// 3. If neither is provided and [policy.evaluateAsync] is set, returns
  ///    `authorized = true` (async evaluation is handled by the widget layer).
  AuthorizationResult evaluate(
    UserSecurityContext context,
    ZenithPolicy policy,
  ) {
    // Evaluate synchronous requirements list.
    final reqs = policy.requirements;
    if (reqs != null && reqs.isNotEmpty) {
      for (final req in reqs) {
        if (!req.evaluate(context)) {
          return AuthorizationResult(
            isAuthorized: false,
            reason: 'Requirement ${req.runtimeType} not satisfied.',
          );
        }
      }
      return const AuthorizationResult(isAuthorized: true);
    }

    // Evaluate sync lambda.
    final evalFn = policy.evaluate;
    if (evalFn != null) {
      final ref = PolicyRef();
      final result = evalFn(ref);
      return AuthorizationResult(isAuthorized: result);
    }

    // Async policy — authorization deferred to widget layer.
    return const AuthorizationResult(isAuthorized: false, reason: 'Pending async evaluation');
  }
}
