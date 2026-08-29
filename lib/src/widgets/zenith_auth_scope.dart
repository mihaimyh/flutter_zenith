import 'package:flutter/widgets.dart';

import '../identity/zenith_identity_auth_state.dart';
import '../identity/zenith_identity_coordinator.dart';
import '../scope/zenith_scope_manager.dart';
import 'zenith_scope_provider.dart';

/// A widget that declaratively switches between authenticated and unauthenticated
/// UI based on a [ZenithIdentityCoordinator]'s state.
///
/// On sign-out or revocation, [ZenithAuthScope] unwinds the navigation stack
/// **before** disposing the scope container, preventing red-screen exceptions
/// from widgets accessing disposed scopes during pop transitions.
///
/// ```dart
/// ZenithAuthScope(
///   coordinator: coordinator,
///   authenticatedBuilder: (context, scope) => HomeScreen(scope: scope),
///   unauthenticatedBuilder: (context) => LoginScreen(),
/// )
/// ```
class ZenithAuthScope extends StatefulWidget {
  /// The coordinator whose state drives this widget.
  final ZenithIdentityCoordinator coordinator;

  /// Builder rendered when the coordinator is in any authenticated state.
  final Widget Function(BuildContext context, ZenithTenantScope scope)
      authenticatedBuilder;

  /// Builder rendered when the coordinator is [AuthUnauthenticated].
  final Widget Function(BuildContext context) unauthenticatedBuilder;

  /// Creates a [ZenithAuthScope].
  const ZenithAuthScope({
    super.key,
    required this.coordinator,
    required this.authenticatedBuilder,
    required this.unauthenticatedBuilder,
  });

  @override
  State<ZenithAuthScope> createState() => _ZenithAuthScopeState();
}

class _ZenithAuthScopeState extends State<ZenithAuthScope> {
  ZenithAuthState? _lastState;
  ZenithTenantScope? _lastScope;

  @override
  void initState() {
    super.initState();
    _lastState = widget.coordinator.state;
    _lastScope = widget.coordinator.currentScope;
    widget.coordinator.addListener(_onCoordinatorChanged);
  }

  @override
  void didUpdateWidget(covariant ZenithAuthScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.coordinator, oldWidget.coordinator)) {
      oldWidget.coordinator.removeListener(_onCoordinatorChanged);
      widget.coordinator.addListener(_onCoordinatorChanged);
      _checkStateChange();
    }
  }

  @override
  void dispose() {
    widget.coordinator.removeListener(_onCoordinatorChanged);
    super.dispose();
  }

  void _onCoordinatorChanged() {
    _checkStateChange();
  }

  void _checkStateChange() {
    final newState = widget.coordinator.state;
    final newScope = widget.coordinator.currentScope;

    if (!identical(newState, _lastState) || !identical(newScope, _lastScope)) {
      final wasAuthenticated = _lastState != null &&
          _lastState is! AuthUnauthenticated;
      final isNowUnauthenticated = newState is AuthUnauthenticated;

      if (wasAuthenticated && isNowUnauthenticated) {
        // Unwind navigation before rebuilding to avoid red-screen on scope disposal.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            // Pop all routes above the root.
            final navigator = Navigator.maybeOf(context);
            if (navigator != null) {
              navigator.popUntil((route) => route.isFirst);
            }
          }
        });
      }

      setState(() {
        _lastState = newState;
        _lastScope = newScope;
      });
    }
  }

  ZenithAuthState get _state => widget.coordinator.state;
  ZenithTenantScope? get _scope => widget.coordinator.currentScope;

  @override
  Widget build(BuildContext context) {
    final state = _state;
    final scope = _scope;

    if (state is AuthUnauthenticated) {
      return widget.unauthenticatedBuilder(context);
    }

    if (scope != null && !scope.isDisposed) {
      return ZenithScopeProvider(
        scope: scope,
        child: Builder(
          builder: (ctx) => widget.authenticatedBuilder(ctx, scope),
        ),
      );
    }

    return widget.unauthenticatedBuilder(context);
  }
}
