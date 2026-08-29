import 'package:flutter/widgets.dart';

import 'zenith_node.dart';
import 'zenith_widgets.dart';

/// Descriptor for a feature flag in `flutter_zenith`.
///
/// Feature flags control conditional rollouts, remote config toggles, and A/B tests.
///
/// ```dart
/// const newCheckoutFeature = ZenithFeature('new_checkout', defaultValue: false);
/// ```
@immutable
class ZenithFeature {
  /// The unique string identifier for this feature flag.
  final String key;

  /// The fallback default boolean status if no remote override is set.
  final bool defaultValue;

  /// Optional human-readable name or description for admin/debug portals.
  final String? name;

  /// Creates a [ZenithFeature] descriptor.
  const ZenithFeature(this.key, {this.defaultValue = false, this.name});

  /// Evaluates a deterministic percentage rollout for a specific [userId].
  ///
  /// Uses a string hash of `featureKey + userId` to consistently return `true` or
  /// `false` for the same user across app launches.
  static bool percentageRollout(
    int percentage, {
    required String featureKey,
    required String userId,
  }) {
    if (percentage <= 0) return false;
    if (percentage >= 100) return true;

    final combined = '$featureKey:$userId';
    var hash = 0;
    for (var i = 0; i < combined.length; i++) {
      hash = (hash * 31 + combined.codeUnitAt(i)) & 0xFFFFFFFF;
    }

    final bucket = (hash & 0x7FFFFFFF) % 100;
    return bucket < percentage;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is ZenithFeature && other.key == key);

  @override
  int get hashCode => key.hashCode;

  @override
  String toString() => 'ZenithFeature("$key", default: $defaultValue)';
}

/// A reactive [ZenithNode] holding the boolean status of a [ZenithFeature].
class FeatureNode extends ZenithNode<bool> {
  /// The feature descriptor associated with this node.
  final ZenithFeature feature;

  /// Creates a [FeatureNode] with initial [initialValue].
  FeatureNode(this.feature, bool initialValue) : super(initialValue);

  /// Toggles the boolean feature state.
  void toggle() {
    set(!value);
  }
}

/// A widget that reactively renders [enabled] or [disabled] based on a [FeatureNode].
///
/// Only rebuilds when the target [FeatureNode] value changes.
///
/// ```dart
/// ZenithFeatureBuilder(
///   featureNode: newCheckoutNode,
///   enabled: (context) => const NewCheckoutScreen(),
///   disabled: (context) => const LegacyCheckoutScreen(),
/// )
/// ```
class ZenithFeatureBuilder extends StatelessWidget {
  /// The feature node to observe.
  final FeatureNode featureNode;

  /// Builder invoked when the feature flag is `true`.
  final WidgetBuilder enabled;

  /// Optional builder invoked when the feature flag is `false`.
  /// Defaults to rendering [SizedBox.shrink].
  final WidgetBuilder? disabled;

  /// Creates a [ZenithFeatureBuilder].
  const ZenithFeatureBuilder({
    super.key,
    required this.featureNode,
    required this.enabled,
    this.disabled,
  });

  @override
  Widget build(BuildContext context) {
    return ZenithBuilder(
      builder: (context) {
        if (featureNode.value) {
          return enabled(context);
        }
        return disabled?.call(context) ?? const SizedBox.shrink();
      },
    );
  }
}
