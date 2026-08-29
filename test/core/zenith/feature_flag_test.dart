import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zenith/flutter_zenith.dart';

void main() {
  group('ZenithFeature & FeatureNode', () {
    const newPaymentFeature = ZenithFeature(
      'new_payment_gateway',
      defaultValue: false,
    );

    test('FeatureNode initializes with default value', () {
      final node = FeatureNode(newPaymentFeature, newPaymentFeature.defaultValue);

      expect(node.value, isFalse);
      expect(node.feature.key, 'new_payment_gateway');
    });

    test('toggle() flips the feature state', () {
      final node = FeatureNode(newPaymentFeature, false);

      node.toggle();
      expect(node.value, isTrue);

      node.toggle();
      expect(node.value, isFalse);
    });

    test('percentageRollout generates deterministic evaluation per userId', () {
      const feature = ZenithFeature('beta_feature');

      final userAEnabled = ZenithFeature.percentageRollout(
        50,
        featureKey: feature.key,
        userId: 'user_123',
      );

      final userAEnabledAgain = ZenithFeature.percentageRollout(
        50,
        featureKey: feature.key,
        userId: 'user_123',
      );

      // Deterministic per userId
      expect(userAEnabled, equals(userAEnabledAgain));

      // 100% rollout is always true
      expect(
        ZenithFeature.percentageRollout(100, featureKey: feature.key, userId: 'any'),
        isTrue,
      );

      // 0% rollout is always false
      expect(
        ZenithFeature.percentageRollout(0, featureKey: feature.key, userId: 'any'),
        isFalse,
      );
    });
  });

  group('ZenithFeatureBuilder UI integration', () {
    const feature = ZenithFeature('dark_mode_v2');

    testWidgets('renders enabled widget when feature is true, disabled when false', (tester) async {
      final node = FeatureNode(feature, false);

      await tester.pumpWidget(
        MaterialApp(
          home: ZenithFeatureBuilder(
            featureNode: node,
            enabled: (context) => const Text('New UI Enabled'),
            disabled: (context) => const Text('Legacy UI'),
          ),
        ),
      );

      expect(find.text('Legacy UI'), findsOneWidget);
      expect(find.text('New UI Enabled'), findsNothing);

      // Toggle feature flag
      node.set(true);
      await tester.pump();

      expect(find.text('New UI Enabled'), findsOneWidget);
      expect(find.text('Legacy UI'), findsNothing);
    });

    testWidgets('renders SizedBox.shrink when disabled is omitted and feature is false', (tester) async {
      final node = FeatureNode(feature, false);

      await tester.pumpWidget(
        MaterialApp(
          home: ZenithFeatureBuilder(
            featureNode: node,
            enabled: (context) => const Text('VIP Banner'),
          ),
        ),
      );

      expect(find.text('VIP Banner'), findsNothing);

      node.set(true);
      await tester.pump();

      expect(find.text('VIP Banner'), findsOneWidget);
    });
  });
}
