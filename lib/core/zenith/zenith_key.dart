import 'zenith_container.dart';

/// A strongly typed identifier for nodes managed by a [ZenithContainer].
///
/// Equality (and [hashCode]) is based on both the type parameter [T] and an
/// optional [name] label, so `ZenithKey<int>('count')` and
/// `ZenithKey<String>('count')` never collide even though they share a name.
class ZenithKey<T> {
  final String name;

  const ZenithKey([this.name = '']);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is ZenithKey<T> && other.name == name);
  }

  @override
  int get hashCode => Object.hash(T, name);

  @override
  String toString() => 'ZenithKey<$T>("$name")';
}

/// Pairs a [ZenithKey] with a factory override function for testing or
/// scoping. Registering a [ZenithOverride] with a [ZenithContainer] causes
/// [ZenithContainer.getOrCreate] to use [factory] instead of the factory
/// passed at the call site whenever [key] is requested.
class ZenithOverride<T> {
  final ZenithKey<T> key;
  final T Function(ZenithRef ref) factory;

  ZenithOverride(this.key, this.factory);
}
