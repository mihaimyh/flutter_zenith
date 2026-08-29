import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zenith/flutter_zenith.dart';

void main() {
  group('ZenithLogger & PII Redaction', () {
    test('redacts sensitive PII properties automatically', () {
      final memorySink = MemoryRingBufferSink(maxCapacity: 10);
      final logger = ZenithLogger(sinks: [memorySink]);

      logger.info('User login attempted for {userId}', {
        'userId': 'user_123',
        'password': 'SuperSecretPassword!',
        'auth_token': 'Bearer jwt_token_abc',
        'creditCard': '4111222233334444',
      });

      expect(memorySink.logs.length, 1);
      final event = memorySink.logs.first;

      expect(event.properties['userId'], 'user_123');
      expect(event.properties['password'], '[REDACTED]');
      expect(event.properties['auth_token'], '[REDACTED]');
      expect(event.properties['creditCard'], '[REDACTED]');
    });

    test('MemoryRingBufferSink maintains maximum capacity and drops oldest logs', () {
      final memorySink = MemoryRingBufferSink(maxCapacity: 3);
      final logger = ZenithLogger(sinks: [memorySink]);

      logger.info('log 1');
      logger.info('log 2');
      logger.info('log 3');
      expect(memorySink.logs.length, 3);
      expect(memorySink.logs.first.template, 'log 1');

      // Add 4th log: log 1 is evicted
      logger.info('log 4');
      expect(memorySink.logs.length, 3);
      expect(memorySink.logs.first.template, 'log 2');
      expect(memorySink.logs.last.template, 'log 4');
    });

    test('formats template string with properties correctly', () {
      final memorySink = MemoryRingBufferSink(maxCapacity: 5);
      final logger = ZenithLogger(sinks: [memorySink]);

      logger.info('Order {orderId} processed for \${amount}', {
        'orderId': 'ORD-999',
        'amount': 49.99,
      });

      final formatted = memorySink.logs.first.formattedMessage;
      expect(formatted, contains('Order ORD-999 processed for \$49.99'));
    });
  });
}
