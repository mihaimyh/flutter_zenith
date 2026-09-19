import 'dart:async';
import 'package:test/test.dart';
import 'package:flutter_zenith/core/zenith/zenith_container.dart';

void main() {
  test('reset allows overlapping async dispose and recreation', () async {
    final container = ZenithContainer();
    bool dbClosed = false;
    bool newDbOpened = false;

    // First node registers an async dispose
    container.getOrCreateNode('db', (ref) {
      ref.onDisposeAsync(() async {
        await Future.delayed(const Duration(milliseconds: 100));
        dbClosed = true;
      });
      return 'connection1';
    });

    // Reset awaits all async teardowns
    await container.reset();

    // Immediately recreate the node while async dispose is still running
    container.getOrCreateNode('db', (ref) {
      if (!dbClosed) {
        throw StateError(
          'Cannot open new connection before old is closed (File Lock Violation)',
        );
      }
      newDbOpened = true;
      return 'connection2';
    });

    expect(newDbOpened, isTrue);
  });
}
