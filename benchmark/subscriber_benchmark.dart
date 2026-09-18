import 'package:flutter_zenith/core/zenith/zenith_node.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:core';

class DummySubscriber implements ZenithSubscriber {
  @override
  void onNodeChanged(ZenithNode<dynamic> node) {}
}

void main() {
  test('Benchmark subscribers', () {
    final scales = [100, 1000, 5000, 10000];
    print('| N | Subscribe Time (ms) | Unsubscribe Time (ms) |');
    print('|---|---|---|');

    for (final n in scales) {
      final node = ZenithNode<int>(0);
      final subs = List.generate(n, (_) => DummySubscriber());
      
      final handles = <ZenithSubscription>[];
      final sw = Stopwatch()..start();
      for (final sub in subs) {
        handles.add(node.subscribe(sub));
      }
      final subscribeMs = sw.elapsedMilliseconds;
      
      sw.reset();
      for (final handle in handles) {
        handle();
      }
      final unsubscribeMs = sw.elapsedMilliseconds;
      
      print('| $n | $subscribeMs | $unsubscribeMs |');
    }
  });
}
