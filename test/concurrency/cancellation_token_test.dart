import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zenith/zenith_identity.dart';

void main() {
  group('Phase 6: Cancellation Tokens & Socket Draining', () {
    test('Test 6.1: Scope Disposal cancels linked CancellationToken immediately',
        () async {
      final manager = ZenithScopeManager();
      final userScope = manager.getOrCreateScope('user_a');

      var networkCallAborted = false;

      userScope.runWithToken((scopedToken) async {
        scopedToken.onCancel(() => networkCallAborted = true);
        await Future<void>.delayed(const Duration(seconds: 5));
      });

      manager.endScope('user_a');

      expect(networkCallAborted, isTrue);
    });

    test(
        'Test 6.2: Restartable Concurrency physically aborts prior HTTP call via Token',
        () async {
      final runner = ZenithConcurrencyRunner();
      final cancelledQueries = <String>[];

      void search(String query) {
        runner.runAsyncRestartable((token) async {
          token.onCancel(() => cancelledQueries.add(query));
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
      }

      search('query_1');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      search('query_2');

      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(cancelledQueries, contains('query_1'));
      expect(cancelledQueries, isNot(contains('query_2')));
    });
  });
}
