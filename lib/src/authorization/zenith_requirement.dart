/// A security context capturing the claims, roles, and entitlements for a user.
///
/// Passed to [ZenithRequirement.evaluate] and
/// [ZenithAuthorizationService.evaluate] to determine whether a policy grants
/// access.
class UserSecurityContext {
  /// Whether the user is currently authenticated (has a valid session).
  final bool isAuthenticated;

  /// Arbitrary claim map. Typical keys: `'entitlement'`, `'subscription_tier'`.
  final Map<String, dynamic> claims;

  /// Monthly bandwidth consumed in gigabytes, for quota-based requirements.
  final double consumedBandwidthGb;

  /// Role strings (e.g. `'admin'`, `'viewer'`).
  final List<String> roles;

  /// Creates a [UserSecurityContext].
  const UserSecurityContext({
    this.isAuthenticated = false,
    this.claims = const {},
    this.consumedBandwidthGb = 0,
    this.roles = const [],
  });

  /// Returns a flat list of entitlements from [claims] under the key
  /// `'entitlement'`, cast to `List<String>`.
  List<String> get entitlements {
    final raw = claims['entitlement'];
    if (raw is List) return raw.cast<String>();
    return const [];
  }
}

/// Contract for a single authorization condition.
///
/// Implement to express business rules such as feature entitlements, role
/// requirements, or quota checks.
abstract class ZenithRequirement {
  /// Returns `true` if [context] satisfies this requirement.
  bool evaluate(UserSecurityContext context);
}

/// Requires the user to have a valid authenticated session.
class RequireAuthenticatedUser implements ZenithRequirement {
  /// Creates a [RequireAuthenticatedUser] requirement.
  const RequireAuthenticatedUser();

  @override
  bool evaluate(UserSecurityContext context) => context.isAuthenticated;
}

/// Requires the user's entitlements to contain [entitlement].
class RequireEntitlement implements ZenithRequirement {
  /// The entitlement string that must be present.
  final String entitlement;

  /// Creates a [RequireEntitlement] requirement for [entitlement].
  const RequireEntitlement(this.entitlement);

  @override
  bool evaluate(UserSecurityContext context) =>
      context.entitlements.contains(entitlement);
}

/// Requires the user's consumed bandwidth to be under [quotaGb] GB.
class RequireMaxMonthlyBandwidth implements ZenithRequirement {
  /// The maximum allowed bandwidth in GB.
  final double quotaGb;

  /// Creates a [RequireMaxMonthlyBandwidth] requirement with [quotaGb].
  const RequireMaxMonthlyBandwidth({required this.quotaGb});

  @override
  bool evaluate(UserSecurityContext context) =>
      context.consumedBandwidthGb < quotaGb;
}

/// Requires the user to hold [role] in their roles list.
class RequireRole implements ZenithRequirement {
  /// The role string that must be present.
  final String role;

  /// Creates a [RequireRole] requirement for [role].
  const RequireRole(this.role);

  @override
  bool evaluate(UserSecurityContext context) => context.roles.contains(role);
}
