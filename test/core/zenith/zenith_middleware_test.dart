import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zenith/flutter_zenith.dart';

class SanitizeWhitespaceMiddleware extends ZenithMiddleware<String> {
  @override
  String? onWillSet(ZenithNode<String> node, String currentValue, String newValue) {
    return newValue.trim();
  }
}

class BlockNegativeMiddleware extends ZenithMiddleware<int> {
  @override
  int? onWillSet(ZenithNode<int> node, int currentValue, int newValue) {
    if (newValue < 0) return null; // Block write
    return newValue;
  }
}

class AuditLogMiddleware<T> extends ZenithMiddleware<T> {
  final List<String> logs = <String>[];

  @override
  void onDidSet(ZenithNode<T> node, T value) {
    logs.add('didSet:$value');
  }
}

void main() {
  group('ZenithMiddleware', () {
    test('onWillSet can sanitize or transform incoming values', () {
      final node = ZenithNode<String>(
        '',
        middleware: [SanitizeWhitespaceMiddleware()],
      );

      node.set('   hello zenith   ');
      expect(node.value, 'hello zenith');
    });

    test('onWillSet returning null blocks the write and suppresses notifications', () {
      final node = ZenithNode<int>(
        10,
        middleware: [BlockNegativeMiddleware()],
      );

      var notifications = 0;
      node.subscribe(_CountingSubscriber(() => notifications++));

      node.set(-5);

      // Node value stays 10
      expect(node.value, 10);
      expect(notifications, 0);

      // Valid set works normally
      node.set(20);
      expect(node.value, 20);
      expect(notifications, 1);
    });

    test('onDidSet fires after successful node mutation', () {
      final audit = AuditLogMiddleware<int>();
      final node = ZenithNode<int>(0, middleware: [audit]);

      node.set(1);
      node.set(2);

      expect(audit.logs, equals(['didSet:1', 'didSet:2']));
    });

    test('middleware pipeline chains modifications in order', () {
      final clampMiddleware = _ClampMiddleware(0, 100);
      final audit = AuditLogMiddleware<int>();

      final node = ZenithNode<int>(0, middleware: [clampMiddleware, audit]);

      node.set(150); // clamped to 100
      expect(node.value, 100);
      expect(audit.logs, equals(['didSet:100']));
    });
  });
}

class _ClampMiddleware extends ZenithMiddleware<int> {
  final int min;
  final int max;

  _ClampMiddleware(this.min, this.max);

  @override
  int? onWillSet(ZenithNode<int> node, int currentValue, int newValue) {
    return newValue.clamp(min, max);
  }
}

class _CountingSubscriber implements ZenithSubscriber {
  final void Function() onNotify;
  _CountingSubscriber(this.onNotify);

  @override
  void onNodeChanged(ZenithNode<dynamic> node) => onNotify();
}
