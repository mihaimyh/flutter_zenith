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

/// Observable startup and shutdown for a registered service.
class ZenithServiceRegistration {
  final ZenithService _service;
  final Completer<void> _started = Completer<void>();
  final Completer<void> _stopped = Completer<void>();
  bool _startupFinished = false;
  bool _stopRequested = false;

  /// Most recent lifecycle failure, also exposed by [started] or [stopped].
  Object? lastError;

  /// Completes when startup succeeds, or throws its error.
  Future<void> get started => _started.future;

  /// Completes after requested shutdown, or throws its error.
  Future<void> get stopped => _stopped.future;

  ZenithServiceRegistration._(this._service, ZenithRef ref) {
    started.ignore();
    stopped.ignore();
    Future<void>.sync(() => _service.onStart(ref)).then(
      (_) {
        _startupFinished = true;
        _started.complete();
      },
      onError: (Object error, StackTrace stack) {
        _startupFinished = true;
        lastError = error;
        _started.completeError(error, stack);
        stop().ignore();
      },
    );
  }

  /// Stops once; if startup is pending, waits before releasing its resources.
  Future<void> stop() {
    if (_stopRequested) return stopped;
    _stopRequested = true;
    final cleanup = _startupFinished
        ? Future<void>.sync(_service.onStop)
        : started
              .then<void>((_) {}, onError: (Object _, StackTrace _) {})
              .then((_) => _service.onStop());
    cleanup.then(
      (_) => _stopped.complete(),
      onError: (Object error, StackTrace stack) {
        lastError = error;
        _stopped.completeError(error, stack);
      },
    );
    return stopped;
  }
}

/// Service registration bound to a ref's asynchronous cleanup.
extension ZenithServiceRefX on ZenithRef {
  /// Starts a service and returns observable lifecycle completion.
  ZenithServiceRegistration registerService(ZenithService service) {
    if (!isMounted) {
      throw StateError('Cannot start a service on a disposed ref');
    }
    final registration = ZenithServiceRegistration._(service, this);
    onDisposeAsync(registration.stop);
    return registration;
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

  Future<void>? _inFlight;

  /// Most recent periodic task error. Task failures do not escape the timer.
  Object? lastError;

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
      if (currentRef != null && currentRef.isMounted && _inFlight == null) {
        _inFlight = Future<void>.sync(() => task(currentRef))
            .then(
              (_) {
                lastError = null;
              },
              onError: (Object error, StackTrace _) {
                lastError = error;
              },
            )
            .whenComplete(() {
              _inFlight = null;
            });
      }
    });
  }

  @override
  Future<void> onStop() async {
    _timer?.cancel();
    _timer = null;
    _ref = null;
    await _inFlight;
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

    final spawnedIsolate = await Isolate.spawn(
      entryPoint,
      _receivePort!.sendPort,
    );
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
