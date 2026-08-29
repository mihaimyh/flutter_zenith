import 'package:flutter/material.dart';

import '../scope/zenith_scope_manager.dart';
import 'zenith_scope_provider.dart';

/// BuildContext extension providing [zenithShowModalBottomSheet], a drop-in
/// replacement for [showModalBottomSheet] that preserves the parent
/// [ZenithTenantScope] across the Navigator boundary.
///
/// Standard [showModalBottomSheet] creates a new route, breaking the
/// [InheritedWidget] chain and making scope-resolved dependencies unavailable
/// in the sheet's [BuildContext]. [zenithShowModalBottomSheet] re-injects a
/// [ZenithScopeProvider] into the sheet so that `sheetContext.zenith(key)`
/// resolves correctly.
///
/// ```dart
/// context.zenithShowModalBottomSheet(
///   builder: (sheetContext) => Text(sheetContext.zenith(userAliasKey)),
/// );
/// ```
extension ZenithScopeBridgeX on BuildContext {
  /// Shows a modal bottom sheet with the parent [ZenithTenantScope] tunnelled
  /// into the sheet's widget subtree.
  Future<T?> zenithShowModalBottomSheet<T>({
    required Widget Function(BuildContext sheetContext) builder,
    bool isScrollControlled = false,
    bool useRootNavigator = false,
    bool isDismissible = true,
    Color? backgroundColor,
    ShapeBorder? shape,
  }) {
    final scope = ZenithScopeProvider.maybeOf(this);
    return showModalBottomSheet<T>(
      context: this,
      isScrollControlled: isScrollControlled,
      useRootNavigator: useRootNavigator,
      isDismissible: isDismissible,
      backgroundColor: backgroundColor,
      shape: shape,
      builder: (sheetContext) => scope != null
          ? ZenithScopeProvider(
              scope: scope,
              child: Builder(builder: builder),
            )
          : Builder(builder: builder),
    );
  }
}
