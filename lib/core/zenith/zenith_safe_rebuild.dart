import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Defers [State.setState] (and other UI work) when Flutter is already
/// building, laying out, or painting.
///
/// Node writes that happen inside a [build] method notify [ZenithBuilder]
/// subscribers synchronously. Calling [setState] on a widget that is not a
/// descendant of the currently-building element throws:
/// `setState() or markNeedsBuild() called during build`.
///
/// This mixin matches the defensive pattern used by `provider`: run immediately
/// in [SchedulerPhase.idle] / [SchedulerPhase.postFrameCallbacks], otherwise
/// schedule a single post-frame callback.
mixin ZenithSafeRebuild<T extends StatefulWidget> on State<T> {
  var _callbackScheduled = false;

  /// True while this [State] is executing [State.build].
  ///
  /// Override to skip a redundant rebuild when the new value is already being
  /// read in the current build.
  bool get zenithIsBuilding => false;

  /// Runs [fn] now, or after the current frame if a build is in progress.
  void zenithRunSafe(VoidCallback fn) {
    if (!mounted) return;

    final phase = SchedulerBinding.instance.schedulerPhase;
    final safeNow = phase == SchedulerPhase.idle ||
        phase == SchedulerPhase.postFrameCallbacks;

    if (safeNow) {
      fn();
      return;
    }

    if (_callbackScheduled) return;
    _callbackScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _callbackScheduled = false;
      if (mounted) fn();
    });
  }

  /// Marks this [State] dirty, deferring when a frame is already underway.
  void zenithMarkNeedsBuild([VoidCallback? fn]) {
    if (zenithIsBuilding) return;
    zenithRunSafe(() {
      if (!mounted) return;
      setState(fn ?? () {});
    });
  }
}
