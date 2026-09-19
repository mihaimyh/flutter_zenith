// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zenith/flutter_zenith.dart';
import 'package:flutter_zenith/zenith_identity.dart' as identity;

class Subscriber implements ZenithSubscriber {
  @override
  void onNodeChanged(ZenithNode<dynamic> node) {}
}

Future<int> rate(int n) async {
  final pipeline = ZenithResiliencePipeline().withRateLimiter(
    maxRequests: n + 1,
    window: const Duration(minutes: 10),
  );
  final watch = Stopwatch()..start();
  for (var i = 0; i < n; i++) {
    await pipeline.execute(() async => 1);
  }
  return watch.elapsedMicroseconds;
}

Future<int> outbox(int n) async {
  final box = identity.ZenithOutboxEngine()..setActiveTenant('a');
  for (var i = 0; i < n; i++) {
    box.enqueue(tenantId: 'a', action: 'sync', payload: {'i': i});
  }
  final watch = Stopwatch()..start();
  await box.flush((_) async {});
  return watch.elapsedMicroseconds;
}

Future<int> subscriptions(int n) async {
  final node = ZenithNode(0);
  final subscriber = Subscriber();
  final watch = Stopwatch()..start();
  final handles = List.generate(n, (_) => node.subscribe(subscriber));
  node.value = 1;
  for (final handle in handles) {
    handle();
  }
  final elapsed = watch.elapsedMicroseconds;
  node.dispose();
  return elapsed;
}

void main() {
  test('scaling benchmark', () async {
    for (final operation in {
      'rate limiter': rate,
      'outbox flush': outbox,
      'subscription lifecycle': subscriptions,
    }.entries) {
      await operation.value(1000);
      for (final n in [100, 1000, 10000]) {
        final samples = <int>[];
        for (var repeat = 0; repeat < 7; repeat++) {
          samples.add(await operation.value(n));
        }
        samples.sort();
        print(
          '${operation.key} N=$n median_us=${samples[3]} samples_us=$samples',
        );
      }
    }
  });
}
