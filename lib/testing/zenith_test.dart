import '../core/zenith/zenith_container.dart';
import '../core/zenith/zenith_environment.dart';
import '../core/zenith/zenith_key.dart';

/// Builds a [ZenithContainer] with typed dependency overrides for tests.
class ZenithTestContainerBuilder {
  final List<ZenithOverride<dynamic>> _overrides =
      <ZenithOverride<dynamic>>[];

  /// Overrides [key] with [factory] in the built test container.
  ZenithTestContainerBuilder override<T>(
    ZenithKey<T> key,
    T Function(ZenithRef ref) factory,
  ) {
    _overrides.add(ZenithOverride<T>(key, factory));
    return this;
  }

  /// Creates the configured test container.
  ZenithContainer build({ZenithContainer? parent}) {
    return ZenithContainer(
      parent: parent,
      environment: ZenithEnvironment.development,
      overrides: _overrides,
    );
  }
}