import 'dart:async';
import 'dart:isolate';

import 'zenith_container.dart';

/// Abstract contract for background hosted services bound to container scope lifecycles.
///
/// Equivalent to `IHostedService` / `BackgroundService` in ASP.NET Core.
///
/// Implement [onStart] to perform background initialization (e.g., establishing WebSockets,
/// starting polling timers, subscribing to event streams) and [onStop] to perform cleanup
/// when the container scope is reset or disposed.
///
/// ```dart
/// class MyBackgroundSyncService extends ZenithService {
///   @override
///   Future<void> onStart(ZenithRef ref) async {
///     // Start background task
///   }
///
///   @override
///   Future<void> onStop() async {
///     // Teardown
///   }
/// }
/// ```
abstract class ZenithService {
  /// Called when this service is registered with a [ZenithRef].
  Future<void> onStart(ZenithRef ref) async {}

  /// Called when the owning [ZenithContainer] or [ZenithRef] scope is disposed/reset.
  Future<void> onStop() async {}
}

/// Extension on [ZenithRef] providing background service lifecycle registration.
extension ZenithServiceRefX on ZenithRef {
  /// Registers [service] with this ref's scope.
  ///
  /// Immediately invokes [ZenithService.onStart] and hooks [ZenithService.onStop]
  /// to run automatically when this scope is disposed or reset.
  void registerService(ZenithService service) {
    service.onStart(this);
    onDispose(() {
      service.onStop();
    });
  }
}

/// A background service that runs a periodic [task] every [interval] duration.
///
/// Automatically creates a [Timer.periodic] on start and cancels it when the
/// container scope disposes or resets.
class ZenithPeriodicService extends ZenithService {
  /// The time interval between periodic task executions.
  final Duration interval;

  /// The async task callback executed on every tick.
  final Future<void> Function(ZenithRef ref) task;

  Timer? _timer;
  ZenithRef? _ref;

  /// Creates a [ZenithPeriodicService].
  ZenithPeriodicService({required this.interval, required this.task});

  @override
  Future<void> onStart(ZenithRef ref) async {
    _ref = ref;
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) {
      final currentRef = _ref;
      if (currentRef != null && currentRef.isMounted) {
        task(currentRef);
      }
    });
  }

  @override
  Future<void> onStop() async {
    _timer?.cancel();
    _timer = null;
    _ref = null;
  }
}

/// A background service that spawns a dedicated background Dart [Isolate] worker.
///
/// Spawns an isolate on start with a [ReceivePort]/[SendPort] pipeline for background
/// event streams, and automatically terminates the isolate when the container scope disposes.
class ZenithIsolateService<T, R> extends ZenithService {
  /// Entry point function executed inside the background Isolate.
  final void Function(SendPort sendPort) entryPoint;

  /// Callback executed on the main thread whenever the background Isolate sends data.
  final void Function(T data)? onData;

  Isolate? _isolate;
  ReceivePort? _receivePort;
  StreamSubscription<dynamic>? _subscription;

  /// Creates a [ZenithIsolateService].
  ZenithIsolateService({required this.entryPoint, this.onData});

  /// Whether the background Isolate worker is currently active.
  bool get isAlive => _isolate != null;

  @override
  Future<void> onStart(ZenithRef ref) async {
    _receivePort = ReceivePort();
    _subscription = _receivePort!.listen((message) {
      if (message is T && onData != null) {
        onData!(message);
      }
    });

    final spawnedIsolate = await Isolate.spawn(entryPoint, _receivePort!.sendPort);
    if (_receivePort == null) {
      // Scope was disposed while Isolate.spawn was awaiting in flight
      spawnedIsolate.kill(priority: Isolate.immediate);
      return;
    }
    _isolate = spawnedIsolate;
  }

  @override
  Future<void> onStop() async {
    final sub = _subscription;
    final port = _receivePort;
    final iso = _isolate;

    _subscription = null;
    _receivePort = null;
    _isolate = null;

    await sub?.cancel();
    port?.close();
    iso?.kill(priority: Isolate.immediate);
  }
}
