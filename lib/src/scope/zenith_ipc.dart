import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

/// An inter-isolate invalidation message that is safe to send across isolate
/// boundaries (contains only plain Dart primitives).
///
/// Background sync isolates broadcast these when they have written new data,
/// so the foreground isolate can invalidate cached reactive nodes without
/// restarting the app.
class ZenithInvalidateMessage {
  /// The tenant (user) id whose node should be invalidated.
  final String tenantId;

  /// The string key of the node to invalidate.
  final String nodeKey;

  /// Creates a [ZenithInvalidateMessage] for [tenantId] / [nodeKey].
  const ZenithInvalidateMessage({
    required this.tenantId,
    required this.nodeKey,
  });
}

/// Internal bookkeeping for a ReceivePort listener registered via
/// [ZenithTenantScope.listenToInterIsolateInvalidations].
class IpcListenerEntry {
  final String _portName;
  final String _tenantId;
  final void Function(String key) _onInvalidate;
  final ReceivePort _port;
  late final StreamSubscription<dynamic> _subscription;

  IpcListenerEntry(this._portName, this._tenantId, this._onInvalidate)
      : _port = ReceivePort() {
    // Clear any stale mapping then register freshly.
    IsolateNameServer.removePortNameMapping(_portName);
    IsolateNameServer.registerPortWithName(_port.sendPort, _portName);

    _subscription = _port.listen((message) {
      if (message is ZenithInvalidateMessage &&
          message.tenantId == _tenantId) {
        _onInvalidate(message.nodeKey);
      }
    });
  }

  /// Cancels this IPC listener and unregisters the port name.
  void cancel() {
    _subscription.cancel();
    _port.close();
    IsolateNameServer.removePortNameMapping(_portName);
  }
}
