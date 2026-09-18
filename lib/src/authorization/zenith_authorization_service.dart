import '../../core/zenith/async_value.dart';
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
  String toString() =>
      'AuthorizationResult(isAuthorized: $isAuthorized'
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

  /// All supplied conditions must pass. Empty or throwing policies deny access.
  /// Async loading and error states never grant access.
  AuthorizationResult evaluate(
    UserSecurityContext context,
    ZenithPolicy policy,
  ) {
    final state = evaluateState(context, policy);
    return AuthorizationResult(
      isAuthorized: state is AsyncData<bool> && state.value,
      reason: state is AsyncLoading<bool> ? 'Pending async evaluation' : null,
    );
  }

  /// Shared evaluation for route guards and reactive authorization widgets.
  AsyncValue<bool> evaluateState(
    UserSecurityContext context,
    ZenithPolicy policy, {
    PolicyRef? ref,
  }) {
    final requirements = policy.requirements ?? const <ZenithRequirement>[];
    if (requirements.isEmpty &&
        policy.evaluate == null &&
        policy.evaluateAsync == null) {
      return const AsyncData(false);
    }
    try {
      for (final requirement in requirements) {
        if (!requirement.evaluate(context)) return const AsyncData(false);
      }
      final policyRef = ref ?? PolicyRef();
      if (policy.evaluate != null && !policy.evaluate!(policyRef)) {
        return const AsyncData(false);
      }
      return policy.evaluateAsync?.call(policyRef) ?? const AsyncData(true);
    } catch (_) {
      return const AsyncData(false);
    }
  }
}
