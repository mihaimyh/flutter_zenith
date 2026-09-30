# DI & lifecycle API reference

From `lib/core/zenith/zenith_container.dart`, `zenith_key.dart`, `zenith_environment.dart`, `zenith_service.dart`, `testing/zenith_test.dart`.

## ZenithContainer

```dart
typedef NodeKey = Object;

ZenithContainer({
  ZenithContainer? parent,
  ZenithEnvironment environment = ZenithEnvironment.production,
  bool isScopedContainer = false,
  List<ZenithOverride<dynamic>> overrides = const [],
  Map<ZenithEnvironment, List<ZenithOverride<dynamic>>> environmentOverrides = const {},
});

final ZenithContainer? parent;
final ZenithEnvironment environment;
final bool isScopedContainer;
bool get isDisposed;
Future<void> get disposalComplete;

ZenithNode<T> getOrCreateNode<T>(NodeKey key, T Function(ZenithRef ref) factory);
ZenithNode<T> getOrCreate<T>(ZenithKey<T> key, T Function(ZenithRef ref) factory);
ZenithNode<T>? maybeNode<T>(NodeKey key);              // local only
ZenithNode<T>? maybeReadKey<T>(ZenithKey<T> key);     // walks parent chain
void invalidate(NodeKey key);                          // bubbles to parent if absent
void invalidateKey<T>(ZenithKey<T> key);

Future<void> reset({bool purgeZeroize = false});       // reusable teardown
void dispose({bool purgeZeroize = false});             // idempotent
Future<void> disposeAsync({bool purgeZeroize = false});
```

Throws `StateError` on `getOrCreate*` when the container is disposed. Throws `ZenithCaptiveDependencyException` when a singleton registration resolves a scoped key from a scoped container.

## ZenithRef

```dart
ZenithRef(ZenithContainer container);

final ZenithContainer container;
bool get isMounted;
T read<T>(ZenithNode<T> node);
void set<T>(ZenithNode<T> node, T value);
Future<void> runAsync<T>(ZenithNode<AsyncValue<T>> node, Future<T> Function() task);
void onDispose(void Function() callback);
void onDisposeAsync(Future<void> Function() callback);
```

## Keys, overrides, families

```dart
class ZenithKey<T> { const ZenithKey([String name = '']); final String name; }
// == is (same runtimeType && same name); hashCode = Object.hash(T, name)

class ZenithOverride<T> {
  ZenithOverride(ZenithKey<T> key, T Function(ZenithRef ref) factory);
  final ZenithKey<T> key;
  final T Function(ZenithRef ref) factory;
}

class ZenithFamily<T, Arg> {
  const ZenithFamily(String name);
  ZenithKey<T> call(Arg argument);
  ZenithFamilyRegistry<T, Arg> registry();
}

class ZenithFamilyRegistry<T, Arg> {
  ZenithFamilyRegistry(ZenithFamily<T, Arg> family);
  final ZenithFamily<T, Arg> family;
  ZenithKey<T> key(Arg argument);
  Iterable<Arg> get arguments;
  void invalidateAll(ZenithContainer container);
  void forget(Arg argument);
  void forgetAll();
}
```

## Environments

```dart
enum ZenithEnvironment { development, staging, production }
```

## Scope widget

```dart
ZenithScope({required ZenithContainer container, required Widget child});
static ZenithContainer ZenithScope.of(BuildContext context);
```

## Background services

```dart
abstract class ZenithService {
  Future<void> onStart(ZenithRef ref) async {}
  Future<void> onStop() async {}
}

class ZenithServiceRegistration {
  Object? lastError;
  Future<void> get started;
  Future<void> get stopped;
  Future<void> stop();
}

extension ZenithServiceRefX on ZenithRef {
  ZenithServiceRegistration registerService(ZenithService service); // throws if ref disposed
}

class ZenithPeriodicService extends ZenithService {
  ZenithPeriodicService({required Duration interval, required Future<void> Function(ZenithRef ref) task});
  final Duration interval;
  final Future<void> Function(ZenithRef ref) task;
  Object? lastError;
}

class ZenithIsolateService<T, R> extends ZenithService {
  ZenithIsolateService({required void Function(SendPort sendPort) entryPoint, void Function(T data)? onData});
  bool get isAlive;
}
```

## Testing

```dart
class ZenithTestContainerBuilder {
  ZenithTestContainerBuilder override<T>(ZenithKey<T> key, T Function(ZenithRef ref) factory);
  ZenithContainer build({ZenithContainer? parent}); // environment: development
}
```

## Zeroizable

```dart
abstract interface class Zeroizable {
  void zeroize();
  bool get isZeroized;
}
```
