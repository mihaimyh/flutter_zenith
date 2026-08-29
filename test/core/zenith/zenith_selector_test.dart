import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zenith/flutter_zenith.dart';

void main() {
  group('ZenithSelector', () {
    testWidgets('only rebuilds when selected value changes', (tester) async {
      final node = ZenithNode<List<String>>(['Alice', 'Bob', 'Charlie']);
      var buildCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: ZenithSelector<List<String>, String>(
            node: node,
            selector: (items) => items[0],
            builder: (context, name) {
              buildCount++;
              return Text(name, textDirection: TextDirection.ltr);
            },
          ),
        ),
      );

      expect(buildCount, 1);
      expect(find.text('Alice'), findsOneWidget);

      // Change an element that is NOT selected.
      node.set(['Alice', 'Bobby', 'Charlie']);
      await tester.pump();

      // No rebuild — selected value (items[0]) is still 'Alice'.
      expect(buildCount, 1);

      // Change the selected element.
      node.set(['Zara', 'Bobby', 'Charlie']);
      await tester.pump();

      expect(buildCount, 2);
      expect(find.text('Zara'), findsOneWidget);
    });

    testWidgets('handles node swap via didUpdateWidget', (tester) async {
      final nodeA = ZenithNode<int>(10);
      final nodeB = ZenithNode<int>(20);

      Widget buildSelector(ZenithNode<int> node) {
        return MaterialApp(
          home: ZenithSelector<int, String>(
            node: node,
            selector: (v) => 'val:$v',
            builder: (context, selected) => Text(selected),
          ),
        );
      }

      await tester.pumpWidget(buildSelector(nodeA));
      expect(find.text('val:10'), findsOneWidget);

      await tester.pumpWidget(buildSelector(nodeB));
      expect(find.text('val:20'), findsOneWidget);

      // Old node should be unsubscribed.
      expect(nodeA.debugSubscriberCount, 0);
      expect(nodeB.debugSubscriberCount, 1);
    });

    testWidgets('unsubscribes on dispose', (tester) async {
      final node = ZenithNode<int>(1);

      await tester.pumpWidget(
        MaterialApp(
          home: ZenithSelector<int, int>(
            node: node,
            selector: (v) => v,
            builder: (context, v) => Text('$v'),
          ),
        ),
      );

      expect(node.debugSubscriberCount, 1);

      await tester.pumpWidget(const SizedBox.shrink());

      expect(node.debugSubscriberCount, 0);
    });
  });

  group('ZenithBuilder errorBuilder', () {
    testWidgets('renders errorBuilder when builder throws', (tester) async {
      final node = ZenithNode<int>(0);
      node.dispose(); // force a throw on .value read

      await tester.pumpWidget(
        MaterialApp(
          home: ZenithBuilder(
            builder: (context) {
              return Text('${node.value}'); // will throw
            },
            errorBuilder: (context, error, stack) {
              return const Text('Error caught');
            },
          ),
        ),
      );

      expect(find.text('Error caught'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('rethrows when no errorBuilder is set', (tester) async {
      final node = ZenithNode<int>(0);
      node.dispose();

      await tester.pumpWidget(
        MaterialApp(
          home: ZenithBuilder(
            builder: (context) {
              return Text('${node.value}');
            },
          ),
        ),
      );

      final exception = tester.takeException();
      expect(exception, isA<StateError>());
    });
  });
}
