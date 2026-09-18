import 'package:test/test.dart';
import 'package:flutter_zenith/src/scope/zenith_scope_manager.dart';
import 'dart:async';

void main() {
  test('runGuarded synchronous throw becomes unhandled async exception (no longer swallowed)', () async {
    final scope = ZenithScopeManager().getOrCreateScope('test_scope');
    
    bool exceptionCaught = false;

    await runZonedGuarded(() async {
      scope.runGuarded(() {
        throw Exception('Sync throw!');
      });
      // Let the event loop process the async error
      await Future.delayed(const Duration(milliseconds: 10));
    }, (e, s) {
      exceptionCaught = true;
    });
    
    expect(exceptionCaught, isTrue, reason: 'Sync throw should propagate to zone error handler.');
    
    // Clean up
    scope.dispose();
  });
}
