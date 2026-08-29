import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zenith/flutter_zenith.dart';

class CustomSyncService extends ZenithService {
  bool isStarted = false;
  bool isStopped = false;

  @override
  Future<void> onStart(ZenithRef ref) async {
    isStarted = true;
  }

  @override
  Future<void> onStop() async {
    isStopped = true;
  }
}

void main() {
  group('ZenithService lifecycle', () {
    test('registerService calls onStart and hooks onStop to scope disposal', () async {
      final container = ZenithContainer();
      final service = CustomSyncService();

      container.getOrCreateNode('service_host', (ref) {
        ref.registerService(service);
        return true;
      });

      expect(service.isStarted, isTrue);
      expect(service.isStopped, isFalse);

      container.dispose();
      expect(service.isStopped, isTrue);
    });

    test('ZenithPeriodicService executes task periodically and cancels timer on disposal', () async {
      final container = ZenithContainer();
      var executions = 0;

      final periodicService = ZenithPeriodicService(
        interval: const Duration(milliseconds: 10),
        task: (ref) async {
          executions++;
        },
      );

      container.getOrCreateNode('periodic_host', (ref) {
        ref.registerService(periodicService);
        return true;
      });

      await Future<void>.delayed(const Duration(milliseconds: 35));
      expect(executions, greaterThanOrEqualTo(2));

      final countBeforeDispose = executions;
      container.dispose();

      await Future<void>.delayed(const Duration(milliseconds: 30));
      // No further executions after container disposal
      expect(executions, equals(countBeforeDispose));
    });

    test('ZenithIsolateService spawns background worker isolate and kills it on disposal', () async {
      final container = ZenithContainer();
      var isolateResults = 0;

      final isolateService = ZenithIsolateService<int, int>(
        entryPoint: (sendPort) {
          // Isolate entrypoint
          sendPort.send(42);
        },
        onData: (data) {
          isolateResults = data;
        },
      );

      container.getOrCreateNode('isolate_host', (ref) {
        ref.registerService(isolateService);
        return true;
      });

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(isolateResults, 42);

      expect(isolateService.isAlive, isTrue);

      container.dispose();
      expect(isolateService.isAlive, isFalse);
    });
  });
}
