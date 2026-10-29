import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zenith/flutter_zenith.dart';

void main() {
  const key = ZenithKey<int>('shared_counter');

  group('ZenithScope container ownership', () {
    testWidgets('disposeContainer: false keeps a shared container alive', (
      tester,
    ) async {
      final shared = ZenithContainer();
      addTearDown(shared.dispose);
      shared.getOrCreate(key, (_) => 7);

      await tester.pumpWidget(
        ZenithScope(
          container: shared,
          disposeContainer: false,
          child: const SizedBox(),
        ),
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump();

      expect(shared.isDisposed, isFalse);
      expect(shared.getOrCreate(key, (_) => 7).value, 7);
    });

    testWidgets('a replacing scope does not dispose an unowned container', (
      tester,
    ) async {
      final shared = ZenithContainer();
      final owned = ZenithContainer();
      addTearDown(shared.dispose);

      await tester.pumpWidget(
        ZenithScope(
          container: shared,
          disposeContainer: false,
          child: const SizedBox(),
        ),
      );
      await tester.pumpWidget(
        ZenithScope(container: owned, child: const SizedBox()),
      );

      expect(shared.isDisposed, isFalse, reason: 'scope did not own it');
      expect(owned.isDisposed, isFalse);

      await tester.pumpWidget(const SizedBox());
      expect(
        owned.isDisposed,
        isTrue,
        reason: 'default ownership still applies',
      );
    });

    testWidgets('default ownership still disposes the container', (
      tester,
    ) async {
      final owned = ZenithContainer();

      await tester.pumpWidget(
        ZenithScope(container: owned, child: const SizedBox()),
      );
      await tester.pumpWidget(const SizedBox());

      expect(owned.isDisposed, isTrue);
    });
  });
}
