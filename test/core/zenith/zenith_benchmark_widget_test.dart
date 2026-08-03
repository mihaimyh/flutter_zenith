import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zenith/flutter_zenith.dart';

void main() {
  testWidgets('benchmark: isolated rebuild counts remain stable under load', (
    tester,
  ) async {
    const iterations = 250;

    final hotNode = ZenithNode<int>(0);
    final coldNode = ZenithNode<int>(0);

    var parentBuildCount = 0;
    var hotBuilderBuildCount = 0;
    var coldBuilderBuildCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            parentBuildCount++;
            return Column(
              children: [
                ZenithBuilder(
                  builder: (context) {
                    hotBuilderBuildCount++;
                    return Text(
                      'hot:${hotNode.value}',
                      textDirection: TextDirection.ltr,
                    );
                  },
                ),
                ZenithBuilder(
                  builder: (context) {
                    coldBuilderBuildCount++;
                    return Text(
                      'cold:${coldNode.value}',
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

    final stopwatch = Stopwatch()..start();
    for (var i = 1; i <= iterations; i++) {
      hotNode.set(i);
      await tester.pump();
    }
    stopwatch.stop();

    final elapsedMicros = stopwatch.elapsedMicroseconds;
    final rebuildsPerSecond = elapsedMicros == 0
        ? 0.0
        : (hotBuilderBuildCount / elapsedMicros) * 1000000;

    expect(parentBuildCount, 1);
    expect(coldBuilderBuildCount, 1);
    expect(hotBuilderBuildCount, iterations + 1);

    // Dedup should keep each builder subscribed at most once per node.
    expect(hotNode.debugSubscriberCount, 1);
    expect(coldNode.debugSubscriberCount, 1);

    // Keep benchmark values visible in test logs for regression tracking.
    // ignore: avoid_print
    print(
      'Zenith benchmark: iterations=$iterations, '
      'elapsed_us=$elapsedMicros, '
      'rebuilds_per_sec=${rebuildsPerSecond.toStringAsFixed(2)}',
    );
  });
}
