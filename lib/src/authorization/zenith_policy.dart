import 'package:flutter_zenith/core/zenith/async_value.dart';
import 'package:flutter_zenith/core/zenith/zenith_node.dart';

import 'zenith_requirement.dart';

/// A named collection of authorization rules evaluated against a
/// [UserSecurityContext].
///
/// A [ZenithPolicy] supports three evaluation modes — all are optional but at
/// least one must produce a result:
///
/// 1. **[requirements]**: a list of [ZenithRequirement]s evaluated synchronously.
///    All requirements must pass for the policy to succeed.
///
/// 2. **[evaluate]**: a synchronous lambda that receives a [PolicyRef] and
///    returns `true`/`false`. Ideal for reactive node-based checks
///    (e.g. `ref.watch(entitlementNode).contains('pro_tier')`).
///
/// 3. **[evaluateAsync]**: an async lambda that returns a
///    `PolicyRef → AsyncValue<bool>` for async receipt verification.
///
/// ```dart
/// final policy = ZenithPolicy(
///   name: 'CanExport4K',
///   requirements: [RequireAuthenticatedUser(), RequireEntitlement('export_4k')],
/// );
/// ```
class ZenithPolicy {
  /// A human-readable name for this policy (used in logs and error messages).
  final String name;

  /// Synchronous list of requirements — all must pass.
  final List<ZenithRequirement>? requirements;

  /// Reactive sync evaluation lambda.
  final bool Function(PolicyRef ref)? evaluate;

  /// Reactive async evaluation lambda returning [AsyncValue<bool>].
  final AsyncValue<bool> Function(PolicyRef ref)? evaluateAsync;

  /// Creates a [ZenithPolicy] with [name] and at least one evaluation strategy.
  const ZenithPolicy({
    required this.name,
    this.requirements,
    this.evaluate,
    this.evaluateAsync,
  });
}

/// A minimal reactive ref passed to [ZenithPolicy.evaluate] and
/// [ZenithPolicy.evaluateAsync], providing [watch] access to [ZenithNode]s.
class PolicyRef {
  final Map<ZenithNode<dynamic>, dynamic> _cache = {};

  /// Reads the current value of [node], subscribing to future updates
  /// (when used inside [ZenithAuthorizeView]).
  T watch<T>(ZenithNode<T> node) {
    _cache[node] = node.value;
    return node.value;
  }
}
