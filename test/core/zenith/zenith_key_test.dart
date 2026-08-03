import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zenith/flutter_zenith.dart';

class CounterController {
  int value;
  CounterController(this.value);
}

final counterKey = ZenithKey<CounterController>('counter');

void main() {
  group('Zenith Type-Safe Dependency Injection Tests', () {
    test('ZenithKey equality relies on Type and name', () {
      final key1 = ZenithKey<CounterController>('counter');
      final key2 = ZenithKey<CounterController>('counter');
      final key3 = ZenithKey<CounterController>('different');

      expect(key1, equals(key2));
      expect(key1, isNot(equals(key3)));
    });

    test('Container creates and caches node via ZenithKey', () {
      final container = ZenithContainer();
      final node1 = container.getOrCreate(
        counterKey,
        (ref) => CounterController(0),
      );
      final node2 = container.getOrCreate(
        counterKey,
        (ref) => CounterController(100),
      );

      expect(node1.value.value, equals(0));
      expect(identical(node1, node2), isTrue);
    });

    test('Container overrides factory when ZenithOverride is provided', () {
      final container = ZenithContainer(
        overrides: [
          ZenithOverride<CounterController>(
            counterKey,
            (ref) => CounterController(999), // Mock/Override value
          ),
        ],
      );

      final node = container.getOrCreate(
        counterKey,
        (ref) => CounterController(0),
      );

      expect(node.value.value, equals(999));
    });
  });
}
