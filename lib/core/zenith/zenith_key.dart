import 'zenith_container.dart';

/// A strongly typed identifier for nodes managed by a [ZenithContainer].
///
/// Equality (and [hashCode]) is based on both the type parameter [T] and an
/// optional [name] label, so `ZenithKey<int>('count')` and
/// `ZenithKey<String>('count')` never collide even though they share a name.
class ZenithKey<T> {
  /// An optional name label to disambiguate keys of the same type.
  final String name;

  /// Creates a [ZenithKey], optionally with a [name] label.
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
  /// The key to override.
  final ZenithKey<T> key;

  /// The replacement factory function.
  final T Function(ZenithRef ref) factory;

  /// Creates a [ZenithOverride] that replaces the factory for [key].
  ZenithOverride(this.key, this.factory);
}

/// A strongly typed family identifier that creates a [ZenithKey] for any [argument].
class ZenithFamily<T, Arg> {
  /// The prefix name for this family.
  final String name;

  /// Creates a [ZenithFamily] with the given [name].
  const ZenithFamily(this.name);

  /// Resolves the specific [ZenithKey] for [argument].
  ZenithKey<T> call(Arg argument) => ZenithKey<T>('$name#$argument');

  /// Creates a registry for tracking family keys in one container scope.
  ZenithFamilyRegistry<T, Arg> registry() => ZenithFamilyRegistry<T, Arg>(this);
}

/// Tracks the keys created for one [ZenithFamily] within a logical scope.
///
/// The registry intentionally owns keys only; node ownership remains with the
/// [ZenithContainer]. This allows callers to batch-invalidate a family without
/// coupling the family definition to any particular container lifecycle.
class ZenithFamilyRegistry<T, Arg> {
  /// Creates a registry for [family].
  ZenithFamilyRegistry(this.family);

  /// The family that creates keys for this registry.
  final ZenithFamily<T, Arg> family;
  final Map<Arg, ZenithKey<T>> _keys = <Arg, ZenithKey<T>>{};

  /// Returns the stable key associated with [argument].
  ZenithKey<T> key(Arg argument) =>
      _keys.putIfAbsent(argument, () => family(argument));

  /// Arguments currently tracked by this registry.
  Iterable<Arg> get arguments => _keys.keys;

  /// Invalidates all nodes represented by tracked family keys in [container].
  void invalidateAll(ZenithContainer container) {
    for (final key in _keys.values) {
      container.invalidateKey(key);
    }
  }

  /// Stops tracking [argument]. Existing container state is unchanged.
  void forget(Arg argument) {
    _keys.remove(argument);
  }

  /// Stops tracking all arguments. Existing container state is unchanged.
  void forgetAll() {
    _keys.clear();
  }
}

