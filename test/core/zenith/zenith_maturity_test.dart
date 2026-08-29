import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zenith/flutter_zenith.dart';

void main() {
  test('mutation retains the newest result when executions overlap', () async {
    final container = ZenithContainer();
    final ref = ZenithRef(container);
    final state = container.getOrCreateNode<AsyncValue<int>>(
      'mutation',
      (_) => const AsyncData<int>(0),
    );
    final mutation = ZenithMutation<int>(ref: ref, state: state);
    final first = Completer<int>();

    final firstRun = mutation.run(() => first.future);
    await mutation.run(() async => 2);
    first.complete(1);
    await firstRun;

    expect(state.value.requireValue, 2);
    container.dispose();
  });

  test('scope token becomes stale after invalidation', () {
    final guard = ZenithScopeGuard();
    final token = guard.capture();

    guard.invalidate();

    expect(token.isCurrent, isFalse);
    expect(guard.capture().isCurrent, isTrue);
  });

  test('family registry invalidates every tracked key', () {
    final container = ZenithContainer();
    const family = ZenithFamily<int, String>('counter');
    final registry = family.registry();
    var changes = 0;
    final first = container.getOrCreate(registry.key('first'), (_) => 1);
    final second = container.getOrCreate(registry.key('second'), (_) => 2);
    final subscriber = _Subscriber(() => changes++);
    first.subscribe(subscriber);
    second.subscribe(subscriber);

    registry.invalidateAll(container);

    expect(changes, 2);
    expect(registry.arguments, containsAll(<String>['first', 'second']));
    container.dispose();
  });

  test('test container builder applies a typed override', () {
    const key = ZenithKey<int>('answer');
    final container = ZenithTestContainerBuilder()
        .override<int>(key, (_) => 42)
        .build();

    expect(container.getOrCreate(key, (_) => 0).value, 42);
    container.dispose();
  });
}

class _Subscriber implements ZenithSubscriber {
  _Subscriber(this.onChange);

  final void Function() onChange;

  @override
  void onNodeChanged(ZenithNode<dynamic> node) => onChange();
}