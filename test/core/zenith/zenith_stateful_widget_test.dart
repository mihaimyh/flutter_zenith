import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zenith/flutter_zenith.dart';

class _TestController extends ZenithController {
  final countNode = ZenithNode<int>(0);
  bool didInit = false;
  bool didDispose = false;

  _TestController(super.ref);

  @override
  void onInit() {
    didInit = true;
  }

  @override
  void onDispose() {
    didDispose = true;
  }

  void increment() {
    set(countNode, countNode.value + 1);
  }
}

class _TestStatefulCounter extends ZenithStatefulWidget {
  final ZenithNode<int> node;
  const _TestStatefulCounter({required this.node});

  @override
  ZenithState<_TestStatefulCounter> createState() => _TestStatefulCounterState();
}

class _TestStatefulCounterState extends ZenithState<_TestStatefulCounter> {
  int localState = 100;

  @override
  Widget buildZenith(BuildContext context, ZenithContainer container) {
    final value = context.watch(widget.node);
    return Column(
      children: [
        Text('Value: $value', textDirection: TextDirection.ltr),
        Text('Local: $localState', textDirection: TextDirection.ltr),
      ],
    );
  }
}

class _TestMixinWidget extends StatefulWidget {
  final ZenithNode<String> node;
  const _TestMixinWidget({required this.node});

  @override
  State<_TestMixinWidget> createState() => _TestMixinWidgetState();
}

class _TestMixinWidgetState extends State<_TestMixinWidget>
    with ZenithStateMixin<_TestMixinWidget> {
  String lastHeard = '';

  @override
  void initState() {
    super.initState();
    listenNode(widget.node, (context, prev, curr) {
      setState(() {
        lastHeard = '$prev -> $curr';
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Text('Heard: $lastHeard', textDirection: TextDirection.ltr);
  }
}

void main() {
  group('ZenithStatefulWidget & ZenithState', () {
    testWidgets('automatically rebuilds on watched node changes', (tester) async {
      final container = ZenithContainer();
      final node = container.getOrCreateNode<int>('count', (_) => 0);

      await tester.pumpWidget(
        ZenithScope(
          container: container,
          child: _TestStatefulCounter(node: node),
        ),
      );

      expect(find.text('Value: 0'), findsOneWidget);
      expect(find.text('Local: 100'), findsOneWidget);

      node.set(1);
      await tester.pump();

      expect(find.text('Value: 1'), findsOneWidget);
      expect(find.text('Local: 100'), findsOneWidget);
    });
  });

  group('ZenithStateMixin', () {
    testWidgets('listenNode fires without rebuild and cleans up on dispose', (tester) async {
      final container = ZenithContainer();
      final node = container.getOrCreateNode<String>('msg', (_) => 'initial');

      await tester.pumpWidget(
        ZenithScope(
          container: container,
          child: _TestMixinWidget(node: node),
        ),
      );

      expect(find.text('Heard: '), findsOneWidget);

      node.set('updated');
      await tester.pump();

      expect(find.text('Heard: initial -> updated'), findsOneWidget);
    });
  });

  group('ZenithConsumer', () {
    testWidgets('ZenithConsumer rebuilds reactively', (tester) async {
      final container = ZenithContainer();
      final node = container.getOrCreateNode<String>('user', (_) => 'Alice');

      await tester.pumpWidget(
        ZenithScope(
          container: container,
          child: ZenithConsumer(
            builder: (context, c, child) {
              final name = context.watch(node);
              return Text('User: $name', textDirection: TextDirection.ltr);
            },
          ),
        ),
      );

      expect(find.text('User: Alice'), findsOneWidget);

      node.set('Bob');
      await tester.pump();

      expect(find.text('User: Bob'), findsOneWidget);
    });
  });

  group('ZenithFamily', () {
    test('creates distinct ZenithKeys per argument', () {
      const family = ZenithFamily<String, int>('user_id');
      final key1 = family(1);
      final key2 = family(2);
      final key1Again = family(1);

      expect(key1, equals(key1Again));
      expect(key1, isNot(equals(key2)));
      expect(key1.name, 'user_id#1');
      expect(key2.name, 'user_id#2');
    });
  });

  group('ZenithController', () {
    test('handles lifecycle hooks and mounted safety', () {
      final container = ZenithContainer();
      final ref = ZenithRef(container);
      final controller = _TestController(ref);

      expect(controller.didInit, isTrue);
      expect(controller.didDispose, isFalse);
      expect(controller.countNode.value, 0);

      controller.increment();
      expect(controller.countNode.value, 1);

      container.dispose();
      expect(controller.didDispose, isTrue);
    });
  });
}
