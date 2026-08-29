import 'package:flutter/widgets.dart';
import 'package:flutter_zenith/core/zenith/async_value.dart';
import 'package:flutter_zenith/core/zenith/zenith_node.dart';

import 'zenith_authorization_service.dart';
import 'zenith_policy.dart';

/// A declarative Flutter widget that shows different UI depending on whether
/// a [ZenithPolicy] grants access.
///
/// Reactive: when a [ZenithNode] read inside [policy.evaluate] or
/// [policy.evaluateAsync] changes value, the widget automatically rebuilds.
///
/// ```dart
/// ZenithAuthorizeView(
///   policy: exportPolicy,
///   authorized: (ctx) => const ExportButton(),
///   notAuthorized: (ctx, result) => const PaywallTrigger(),
///   authorizing: (ctx) => const ShimmerPlaceholder(),
/// )
/// ```
class ZenithAuthorizeView extends StatefulWidget {
  /// Builder rendered when the policy grants access.
  final Widget Function(BuildContext context) authorized;

  /// Builder rendered when the policy denies access.
  final Widget Function(BuildContext context, AuthorizationResult result)
  notAuthorized;

  /// Optional builder rendered while an async policy is resolving.
  final Widget Function(BuildContext context)? authorizing;

  /// The policy to evaluate.
  final ZenithPolicy policy;

  /// Creates a [ZenithAuthorizeView].
  const ZenithAuthorizeView({
    super.key,
    required this.policy,
    required this.authorized,
    required this.notAuthorized,
    this.authorizing,
  });

  /// A [ZenithAuthorizeView] that hides the [authorized] widget when denied
  /// (renders [SizedBox.shrink] instead of calling [notAuthorized]).
  factory ZenithAuthorizeView.hidden({
    required ZenithPolicy policy,
    required Widget Function(BuildContext) authorized,
  }) {
    return ZenithAuthorizeView(
      policy: policy,
      authorized: authorized,
      notAuthorized: (_, _) => const SizedBox.shrink(),
    );
  }

  /// A [ZenithAuthorizeView] that shows a locked icon/overlay when denied.
  factory ZenithAuthorizeView.locked({
    required ZenithPolicy policy,
    required Widget Function(BuildContext) authorized,
    Widget Function(BuildContext, AuthorizationResult)? notAuthorized,
  }) {
    return ZenithAuthorizeView(
      policy: policy,
      authorized: authorized,
      notAuthorized:
          notAuthorized ??
          (_, _) => const Icon(IconData(0xe0ee, fontFamily: 'MaterialIcons')),
    );
  }

  @override
  State<ZenithAuthorizeView> createState() => _ZenithAuthorizeViewState();
}

class _ZenithAuthorizeViewState extends State<ZenithAuthorizeView>
    implements ZenithSubscriber {
  final Set<ZenithNode<dynamic>> _subscribedNodes = {};
  _PolicyState _policyState = _Evaluating();

  @override
  void initState() {
    super.initState();
    _evaluate();
  }

  @override
  void didUpdateWidget(covariant ZenithAuthorizeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _evaluate();
  }

  void _evaluate() {
    _clearSubscriptions();
    final policy = widget.policy;

    // Async policy path.
    final asyncEval = policy.evaluateAsync;
    if (asyncEval != null) {
      final ref = _ReactiveRef(onNodeRead: _subscribeToNode);
      final result = asyncEval(ref);
      _setFromAsync(result);
      return;
    }

    // Sync lambda path.
    final syncEval = policy.evaluate;
    if (syncEval != null) {
      final ref = _ReactiveRef(onNodeRead: _subscribeToNode);
      final granted = syncEval(ref);
      _policyState = granted
          ? _Authorized()
          : _Denied(const AuthorizationResult(isAuthorized: false));
      return;
    }

    // Requirements list — no reactive nodes.
    _policyState = _Authorized();
  }

  void _setFromAsync(AsyncValue<bool> value) {
    if (value is AsyncLoading) {
      _policyState = _Evaluating();
    } else if (value is AsyncData<bool>) {
      _policyState = value.value
          ? _Authorized()
          : _Denied(const AuthorizationResult(isAuthorized: false));
    } else {
      _policyState = _Denied(const AuthorizationResult(isAuthorized: false));
    }
  }

  void _subscribeToNode(ZenithNode<dynamic> node) {
    if (_subscribedNodes.add(node)) {
      node.subscribe(this);
    }
  }

  @override
  void onNodeChanged(ZenithNode<dynamic> node) {
    if (!mounted) return;
    setState(_evaluate);
  }

  void _clearSubscriptions() {
    for (final node in _subscribedNodes) {
      node.unsubscribe(this);
    }
    _subscribedNodes.clear();
  }

  @override
  void dispose() {
    _clearSubscriptions();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = _policyState;
    if (state is _Authorized) {
      return widget.authorized(context);
    } else if (state is _Evaluating) {
      return widget.authorizing?.call(context) ?? const SizedBox.shrink();
    } else if (state is _Denied) {
      return widget.notAuthorized(context, state.result);
    }
    return const SizedBox.shrink();
  }
}

// ─── Internal state ──────────────────────────────────────────────────────────

sealed class _PolicyState {}

class _Authorized extends _PolicyState {
  _Authorized();
}

class _Evaluating extends _PolicyState {
  _Evaluating();
}

class _Denied extends _PolicyState {
  final AuthorizationResult result;
  _Denied(this.result);
}

// ─── Reactive ref helper ─────────────────────────────────────────────────────

class _ReactiveRef extends PolicyRef {
  final void Function(ZenithNode<dynamic>) onNodeRead;

  _ReactiveRef({required this.onNodeRead});

  @override
  T watch<T>(ZenithNode<T> node) {
    onNodeRead(node);
    return node.value;
  }
}
