import 'package:flutter/widgets.dart';
import 'package:flutter_zenith/core/zenith/zenith_key.dart';

import '../scope/zenith_scope_manager.dart';

/// An [InheritedWidget] that exposes a [ZenithTenantScope] to its subtree.
///
/// Use [ZenithScopeProvider.of] to retrieve the scope from a descendant
/// [BuildContext], or the [BuildContext.zenithScope] extension.
class ZenithScopeProvider extends InheritedWidget {
  /// The tenant scope available to the subtree.
  final ZenithTenantScope scope;

  /// Creates a [ZenithScopeProvider].
  const ZenithScopeProvider({
    super.key,
    required this.scope,
    required super.child,
  });

  /// Retrieves the nearest [ZenithTenantScope] from [context].
  ///
  /// Asserts that a [ZenithScopeProvider] ancestor exists.
  static ZenithTenantScope of(BuildContext context) {
    final provider =
        context.getInheritedWidgetOfExactType<ZenithScopeProvider>();
    assert(
      provider != null,
      'No ZenithScopeProvider found in the widget tree.',
    );
    return provider!.scope;
  }

  /// Retrieves the nearest [ZenithTenantScope] from [context], or null if none exists.
  static ZenithTenantScope? maybeOf(BuildContext context) {
    return context
        .getInheritedWidgetOfExactType<ZenithScopeProvider>()
        ?.scope;
  }

  @override
  bool updateShouldNotify(covariant ZenithScopeProvider oldWidget) =>
      !identical(oldWidget.scope, scope);
}

/// BuildContext extension for convenient scope resolution.
extension ZenithScopeContextX on BuildContext {
  /// Returns the nearest [ZenithTenantScope] from [ZenithScopeProvider].
  ZenithTenantScope get zenithScope => ZenithScopeProvider.of(this);

  /// Resolves the value for [key] from the nearest [ZenithTenantScope]'s
  /// container, or throws if not registered.
  T zenith<T>(ZenithKey<T> key) {
    final scope = ZenithScopeProvider.of(this);
    final node = scope.container.maybeNode<T>(key);
    if (node == null) {
      throw StateError(
        'No node registered for $key in scope "${scope.id}".',
      );
    }
    return node.value;
  }
}
