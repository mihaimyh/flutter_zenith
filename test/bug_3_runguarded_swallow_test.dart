import 'dart:async';
import 'package:test/test.dart';
import 'package:flutter_zenith/src/scope/zenith_scope_manager.dart';

void main() {
  test('runGuarded swallows unhandled exceptions silently', () async {
    final scope = ZenithScopeManager().getOrCreateScope('test_scope');

    bool exceptionSwallowed = true;

    // We run an async guarded task that THROWS.
    runZonedGuarded(
      () {
        scope.runGuarded(() async {
          throw StateError(
            'This error is completely swallowed and never observed!',
          );
        });
      },
      (error, stack) {
        // If runZonedGuarded catches it, it wasn't swallowed!
        exceptionSwallowed = false;
      },
    );

    // Wait a bit to let the event loop process the async task
    await Future.delayed(const Duration(milliseconds: 100));

    // The test asserts that the exception was correctly propagated
    expect(
      exceptionSwallowed,
      isFalse,
      reason: 'Bug fixed: runGuarded correctly throws exceptions.',
    );
  });
}
