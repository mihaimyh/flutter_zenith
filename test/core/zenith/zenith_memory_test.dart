import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zenith/flutter_zenith.dart';

class _NoopSubscriber implements ZenithSubscriber {
  @override
  void onNodeChanged(ZenithNode<dynamic> node) {}
}

void main() {
  group('Zenith weak-reference behavior', () {
    test('subscribe returns opaque handles that decrement subscriber count', () {
      final node = ZenithNode<int>(0);
      final subscriber = _NoopSubscriber();

      final handle1 = node.subscribe(subscriber);
      final handle2 = node.subscribe(subscriber);

      expect(node.debugSubscriberCount, 2);

      handle1();
      expect(node.debugSubscriberCount, 1);

      handle2();
      expect(node.debugSubscriberCount, 0);
    });

    test('dead weak references are cleaned during notify pass', () async {
      final node = ZenithNode<int>(0);

      void attachEphemeralSubscriber() {
        final ephemeral = _NoopSubscriber();
        node.subscribe(ephemeral);
      }

      attachEphemeralSubscriber();
      expect(node.debugSubscriberCount, 1);

      for (var i = 0; i < 200 && node.debugSubscriberCount > 0; i++) {
        final pressure = List<int>.generate(2000, (index) => index);
        expect(pressure.length, 2000);
        await Future<void>.delayed(const Duration(milliseconds: 5));
        node.notifySubscribers();
      }

      expect(node.debugSubscriberCount, 0);
    });
  });
}
