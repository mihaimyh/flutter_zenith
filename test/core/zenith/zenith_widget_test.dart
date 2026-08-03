import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zenith/flutter_zenith.dart';

void main() {
  testWidgets(
    'mutating node A rebuilds only builder A, not parent or builder B',
    (tester) async {
      final nodeA = ZenithNode<String>('A');
      final nodeB = ZenithNode<String>('B');

      var parentBuildCount = 0;
      var builderABuildCount = 0;
      var builderBBuildCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              parentBuildCount++;
              return Column(
                children: [
                  ZenithBuilder(
                    builder: (context) {
                      builderABuildCount++;
                      return Text(
                        'A:${nodeA.value}',
                        textDirection: TextDirection.ltr,
                      );
                    },
                  ),
                  ZenithBuilder(
                    builder: (context) {
                      builderBBuildCount++;
                      return Text(
                        'B:${nodeB.value}',
                        textDirection: TextDirection.ltr,
                      );
                    },
                  ),
                ],
              );
            },
          ),
        ),
      );

      expect(parentBuildCount, 1);
      expect(builderABuildCount, 1);
      expect(builderBBuildCount, 1);

      nodeA.set('A2');
      await tester.pump();

      expect(parentBuildCount, 1);
      expect(builderABuildCount, 2);
      expect(builderBBuildCount, 1);
    },
  );

  testWidgets(
    'conditional reads unsubscribe stale node dependencies between builds',
    (tester) async {
      final isLoggedInNode = ZenithNode<bool>(true);
      final profileNode = ZenithNode<String>('Alice');

      var buildCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: ZenithBuilder(
            builder: (context) {
              buildCount++;
              if (isLoggedInNode.value) {
                return Text(
                  profileNode.value,
                  textDirection: TextDirection.ltr,
                );
              }
              return const Text('Guest', textDirection: TextDirection.ltr);
            },
          ),
        ),
      );

      expect(buildCount, 1);
      expect(find.text('Alice'), findsOneWidget);

      isLoggedInNode.set(false);
      await tester.pump();

      expect(buildCount, 2);
      expect(find.text('Guest'), findsOneWidget);

      profileNode.set('Bob');
      await tester.pump();

      // No extra rebuild: profileNode should be unsubscribed in Guest branch.
      expect(buildCount, 2);
      expect(find.text('Guest'), findsOneWidget);
    },
  );
}
