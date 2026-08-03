import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zenith/flutter_zenith.dart';

void main() {
  testWidgets('key swap disposes previous scope container state', (
    tester,
  ) async {
    var disposeHookCount = 0;
    late ZenithContainer firstContainer;
    late ZenithNode<int> firstNode;

    Widget appForUser(String userId) {
      final container = ZenithContainer();
      final node = container.getOrCreateNode<int>('counter', (ref) {
        ref.onDispose(() => disposeHookCount++);
        return 1;
      });

      if (userId == 'user_1') {
        firstContainer = container;
        firstNode = node;
      }

      return MaterialApp(
        home: ZenithScope(
          key: ValueKey<String>(userId),
          container: container,
          child: Builder(
            builder: (context) {
              final currentContainer = ZenithScope.of(context);
              final currentNode = currentContainer.maybeNode<int>('counter');
              return Text(
                'value:${currentNode?.value}',
                textDirection: TextDirection.ltr,
              );
            },
          ),
        ),
      );
    }

    await tester.pumpWidget(appForUser('user_1'));

    expect(firstContainer.isDisposed, isFalse);
    expect(firstNode.isDisposed, isFalse);

    await tester.pumpWidget(appForUser('user_2'));

    expect(disposeHookCount, 1);
    expect(firstContainer.isDisposed, isTrue);
    expect(firstNode.isDisposed, isTrue);
    expect(firstContainer.maybeNode<int>('counter'), isNull);
  });
}
