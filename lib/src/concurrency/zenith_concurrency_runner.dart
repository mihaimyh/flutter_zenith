import 'dart:async';

import '../scope/zenith_scope_manager.dart';

/// A concurrency runner that supports the `restartable` pattern via explicit
/// [ZenithCancellationToken]s.
///
/// Unlike [ZenithConcurrencyX.runAsyncGuarded] (which uses generation counters
/// and [AsyncValue] nodes), [ZenithConcurrencyRunner] works with arbitrary
/// `Future<void>` tasks and physically cancels the prior token.
///
/// ```dart
/// final runner = ZenithConcurrencyRunner();
///
/// runner.runAsyncRestartable((token) async {
///   token.onCancel(() => client.abort());
///   await client.search(query);
/// });
/// ```
class ZenithConcurrencyRunner {
  ZenithCancellationToken? _currentToken;

  /// Runs [task] with a fresh [ZenithCancellationToken], cancelling any
  /// previously active task's token before starting.
  ///
  /// This models the `restartable` concurrency strategy: only the latest
  /// invocation's result is relevant; earlier results are discarded.
  void runAsyncRestartable(
    Future<void> Function(ZenithCancellationToken token) task,
  ) {
    // Cancel the prior task.
    _currentToken?.cancel();

    final token = ZenithCancellationToken();
    _currentToken = token;

    task(token).then((_) {
      if (identical(_currentToken, token)) {
        _currentToken = null;
      }
    }).catchError((_) {
      if (identical(_currentToken, token)) {
        _currentToken = null;
      }
    });
  }

  /// Cancels the currently active task, if any.
  void cancelCurrent() {
    _currentToken?.cancel();
    _currentToken = null;
  }
}
