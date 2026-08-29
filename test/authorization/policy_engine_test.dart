import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zenith/zenith_identity.dart';

void main() {
  group('Phase 4: Policy-Based Authorization Engine', () {
    test('Test 4.1: Policy evaluates multiple requirements (Composite Rules)',
        () {
      const authService = ZenithAuthorizationService();

      final proExportPolicy = ZenithPolicy(
        name: 'CanExport4K',
        requirements: [
          RequireAuthenticatedUser(),
          RequireEntitlement('export_4k'),
          RequireMaxMonthlyBandwidth(quotaGb: 50),
        ],
      );

      const userContext = UserSecurityContext(
        isAuthenticated: true,
        claims: {
          'entitlement': ['export_4k'],
        },
        consumedBandwidthGb: 20,
      );

      final result = authService.evaluate(userContext, proExportPolicy);
      expect(result.isAuthorized, isTrue);
    });

    testWidgets(
        'Test 4.2: ZenithAuthorizeView flips from paywall to unlocked on tier upgrade',
        (tester) async {
      final entitlementNode = ZenithNode<List<String>>(['standard_tier']);
      final exportPolicy = ZenithPolicy(
        name: 'ExportPolicy',
        evaluate: (ref) => ref.watch(entitlementNode).contains('pro_tier'),
      );

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ZenithAuthorizeView(
            policy: exportPolicy,
            authorized: (context) => const Text('UNLOCKED_PRO_BUTTON'),
            notAuthorized: (context, result) =>
                const Text('LOCKED_PAYWALL_TRIGGER'),
          ),
        ),
      );

      expect(find.text('LOCKED_PAYWALL_TRIGGER'), findsOneWidget);
      expect(find.text('UNLOCKED_PRO_BUTTON'), findsNothing);

      entitlementNode.value = ['standard_tier', 'pro_tier'];
      await tester.pump();

      expect(find.text('UNLOCKED_PRO_BUTTON'), findsOneWidget);
      expect(find.text('LOCKED_PAYWALL_TRIGGER'), findsNothing);
    });

    testWidgets(
        'Test 4.3: ZenithAuthorizeView renders authorizing shimmer during receipt validation',
        (tester) async {
      final verifyingNode =
          ZenithNode<AsyncValue<bool>>(const AsyncLoading());
      final receiptPolicy = ZenithPolicy(
        name: 'ReceiptValidation',
        evaluateAsync: (ref) => ref.watch(verifyingNode),
      );

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ZenithAuthorizeView(
            policy: receiptPolicy,
            authorized: (context) => const Text('PAID_CONTENT'),
            notAuthorized: (context, _) => const Text('LOCKED_CONTENT'),
            authorizing: (context) => const Text('VALIDATING_RECEIPT_SHIMMER'),
          ),
        ),
      );

      expect(find.text('VALIDATING_RECEIPT_SHIMMER'), findsOneWidget);
      expect(find.text('PAID_CONTENT'), findsNothing);

      verifyingNode.value = const AsyncData(true);
      await tester.pump();

      expect(find.text('PAID_CONTENT'), findsOneWidget);
      expect(find.text('VALIDATING_RECEIPT_SHIMMER'), findsNothing);
    });
  });
}
