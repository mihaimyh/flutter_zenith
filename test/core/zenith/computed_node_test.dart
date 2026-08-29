import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zenith/flutter_zenith.dart';

class _CountingSubscriber implements ZenithSubscriber {
  int count = 0;
  @override
  void onNodeChanged(ZenithNode<dynamic> node) => count++;
}

void main() {
  group('ComputedNode', () {
    test('derives initial value from source nodes', () {
      final firstName = ZenithNode<String>('John');
      final lastName = ZenithNode<String>('Doe');
      final fullName = ComputedNode<String>(
        () => '${firstName.value} ${lastName.value}',
      );

      expect(fullName.value, 'John Doe');
    });

    test('recomputes when a source node changes', () {
      final a = ZenithNode<int>(2);
      final b = ZenithNode<int>(3);
      final sum = ComputedNode<int>(() => a.value + b.value);

      expect(sum.value, 5);

      a.set(10);
      expect(sum.value, 13);

      b.set(7);
      expect(sum.value, 17);
    });

    test('notifies downstream subscribers when derived value changes', () {
      final source = ZenithNode<int>(1);
      final doubled = ComputedNode<int>(() => source.value * 2);
      final subscriber = _CountingSubscriber();
      doubled.subscribe(subscriber);

      source.set(5);
      expect(subscriber.count, 1);
      expect(doubled.value, 10);
    });

    test('does NOT notify when derived value is unchanged', () {
      // source toggles between 5 and 5 — computed clamps to same result.
      final source = ZenithNode<int>(5);
      final clamped = ComputedNode<int>(() {
        final v = source.value;
        return v.clamp(0, 10);
      });

      final subscriber = _CountingSubscriber();
      clamped.subscribe(subscriber);

      source.set(5); // same clamped output → no notify
      expect(subscriber.count, 0);

      source.set(3); // different clamped output
      expect(subscriber.count, 1);
      expect(clamped.value, 3);
    });

    test('reconciles dependencies when branches change', () {
      final flag = ZenithNode<bool>(true);
      final nodeA = ZenithNode<String>('a');
      final nodeB = ZenithNode<String>('b');

      final computed = ComputedNode<String>(
        () => flag.value ? nodeA.value : nodeB.value,
      );

      expect(computed.value, 'a');

      // nodeB is not a dependency right now.
      nodeB.set('b-changed');
      expect(computed.value, 'a'); // still 'a'

      // Switch branch.
      flag.set(false);
      expect(computed.value, 'b-changed');

      // Now nodeA is no longer tracked.
      nodeA.set('a-changed');
      expect(computed.value, 'b-changed'); // no recompute
    });

    test('set() throws StateError', () {
      final source = ZenithNode<int>(1);
      final computed = ComputedNode<int>(() => source.value);

      expect(() => computed.set(99), throwsStateError);
    });

    test('dispose() cleans up subscriptions to source nodes', () {
      final source = ZenithNode<int>(1);
      final computed = ComputedNode<int>(() => source.value * 2);

      expect(source.debugSubscriberCount, 1);

      computed.dispose();
      expect(source.debugSubscriberCount, 0);
      expect(computed.isDisposed, isTrue);
    });

    test('chained ComputedNodes propagate correctly', () {
      final base = ZenithNode<int>(2);
      final doubled = ComputedNode<int>(() => base.value * 2);
      final quadrupled = ComputedNode<int>(() => doubled.value * 2);

      expect(doubled.value, 4);
      expect(quadrupled.value, 8);

      base.set(3);
      expect(doubled.value, 6);
      expect(quadrupled.value, 12);
    });

    test('detects cyclic dependencies and throws StateError', () {
      ComputedNode<int>? nodeA;
      ComputedNode<int>? nodeB;

      final source = ZenithNode<int>(1);

      nodeA = ComputedNode<int>(() => source.value + (nodeB?.value ?? 0));
      nodeB = ComputedNode<int>(() => nodeA!.value + 1);

      expect(() => source.set(2), throwsStateError);
    });
  });
}
