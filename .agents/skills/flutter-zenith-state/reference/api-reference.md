# State API reference

Exact public signatures. From `lib/core/zenith/*`.

## ZenithNode<T>

```dart
ZenithNode<T>(T value, {List<ZenithMiddleware<T>> middleware = const []})

T get value;                       // auto-subscribes when a ZenithZone observer is active
set value(T newValue);             // == set()
bool get isDisposed;
int get debugSubscriberCount;

bool trySet(T newValue);           // false if disposed (no throw)
void set(T newValue);              // equal value / disposed => no-op
void invalidate();                 // force notify; throws if disposed; re-entrancy safe
ZenithSubscription subscribe(ZenithSubscriber subscriber); // throws if disposed
void unsubscribe(ZenithSubscriber subscriber);            // safe after dispose
void notifySubscribers();
void dispose({bool purgeZeroize = false});
```

Supporting types:

```dart
typedef ZenithSubscription = void Function();
abstract class ZenithSubscriber { void onNodeChanged(ZenithNode<dynamic> node); }
abstract class ZenithObserverTracker {
  void onNodeRead(ZenithNode<dynamic> node, ZenithSubscription subscription);
}
class ZenithZone { static ZenithSubscriber? currentObserver; }
```

## ComputedNode<T>

```dart
ComputedNode<T>(T Function() compute);
// extends ZenithNode<T>; set() throws StateError; cyclic deps throw.
```

## ZenithMiddleware<T>

```dart
abstract class ZenithMiddleware<T> {
  T? onWillSet(ZenithNode<T> node, T currentValue, T newValue) => newValue; // null cancels
  void onDidSet(ZenithNode<T> node, T value) {}
}
```

## AsyncValue<T> (sealed)

```dart
R when<R>({
  required R Function(T data) data,
  required R Function(T? previousData) loading,
  required R Function(Object error, StackTrace stackTrace) error,
});
R maybeWhen<R>({..., required R Function() orElse});
R? whenOrNull<R>({...});

T? get valueOrNull;
T get requireValue;   // throws StateError unless AsyncData
bool get isLoading; bool get hasData; bool get hasValue; bool get hasError;
```

```dart
const AsyncData<T>(T value);
const AsyncLoading<T>([T? previousData]);
const AsyncError<T>(Object error, StackTrace stackTrace);
// all three: value equality

extension SafeAsyncNodeX<T> on ZenithNode<AsyncValue<T>> {
  Future<void> guard(ZenithRef ref, Future<T> Function() future);
}
```

## ZenithRef (see also `flutter-zenith-di`)

```dart
bool get isMounted;
T read<T>(ZenithNode<T> node);
void set<T>(ZenithNode<T> node, T value);            // no-op after dispose
Future<void> runAsync<T>(ZenithNode<AsyncValue<T>> node, Future<T> Function() task);
void onDispose(void Function() callback);
void onDisposeAsync(Future<void> Function() callback);
```

## Concurrency extensions

```dart
enum ConcurrencyStrategy { concurrent, droppable, restartable }

extension ZenithConcurrencyX on ZenithRef {
  Future<void> runAsyncGuarded<T>(
    ZenithNode<AsyncValue<T>> node,
    Future<T> Function() task, {
    ConcurrencyStrategy strategy = ConcurrencyStrategy.restartable,
  });
}

extension ZenithIsolateX on ZenithRef {
  Future<void> runInIsolate<T, P>(
    ZenithNode<AsyncValue<T>> node,
    P payload,
    T Function(P payload) heavyComputation, {
    ConcurrencyStrategy strategy = ConcurrencyStrategy.concurrent,
  });
}
```

## ZenithMutation<T>

```dart
ZenithMutation<T>({required ZenithRef ref, required ZenithNode<AsyncValue<T>> state});

final ZenithNode<AsyncValue<T>> state;
bool get isPending;
Future<T?> run(Future<T> Function() operation);
// stale/disposed run => null; current failure => records AsyncError and rethrows
```

## Streams

```dart
extension ZenithStreamX on ZenithRef {
  StreamSubscription<T> watchStream<T>(ZenithNode<AsyncValue<T>> node, Stream<T> stream);
}
extension StreamNodeX<T> on ZenithNode<AsyncValue<T>> {
  StreamSubscription<T> watch(ZenithRef ref, Stream<T> stream);
}
```

## Widgets

```dart
ZenithBuilder({required Widget Function(BuildContext) builder,
               Widget Function(BuildContext, Object error, StackTrace stack)? errorBuilder});
ZenithConsumer({required Widget Function(BuildContext, ZenithContainer, Widget?) builder,
                Widget? child});
abstract class ZenithConsumerWidget extends StatelessWidget {
  const ZenithConsumerWidget({super.key});
  Widget buildConsumer(BuildContext context, ZenithContainer container);
}
abstract class ZenithStatefulWidget extends StatefulWidget {
  @override ZenithState<ZenithStatefulWidget> createState();
}
abstract class ZenithState<T extends ZenithStatefulWidget> extends State<T> {
  ZenithContainer get container;
  Widget buildZenith(BuildContext context, ZenithContainer container);
}
mixin ZenithStateMixin<T extends StatefulWidget> on State<T> {
  ZenithContainer get container;
  void listenNode<V>(ZenithNode<V> node,
      void Function(BuildContext context, V previous, V current) listener);
}
ZenithSelector<T, R>({required ZenithNode<T> node,
                      required R Function(T value) selector,
                      required Widget Function(BuildContext, R selected) builder});
ZenithListener<T>({required ZenithNode<T> node,
                   required void Function(BuildContext, T previous, T current) listener,
                   required Widget child});
```

## BuildContext extensions (core)

```dart
extension ZenithContextX on BuildContext {
  ZenithContainer get container;                               // requires a ZenithScope ancestor
  ZenithNode<T> zenith<T>(ZenithKey<T> key, T Function(ZenithRef) factory);
  T watchNode<T>(ZenithNode<T> node);
  T watch<T>(ZenithNode<T> node);
  R selectNode<T, R>(ZenithNode<T> node, R Function(T state) selector);
  R select<T, R>(ZenithNode<T> node, R Function(T state) selector);
}
```

## Safe rebuild

```dart
mixin ZenithSafeRebuild<T extends StatefulWidget> on State<T> {
  bool get zenithIsBuilding => false;
  void zenithRunSafe(VoidCallback fn);       // runs now, or post-frame if a frame is underway
  void zenithMarkNeedsBuild([VoidCallback? fn]);
}
```

## ZenithController

```dart
abstract class ZenithController {
  final ZenithRef ref;
  ZenithController(this.ref);   // registers onDispose; calls onInit()
  void onInit() {}
  void onDispose() {}
  bool get isMounted;
  void set<T>(ZenithNode<T> node, T value);
  Future<void> runAsync<T>(ZenithNode<AsyncValue<T>> node, Future<T> Function() task);
  StreamSubscription<T> watchStream<T>(ZenithNode<AsyncValue<T>> node, Stream<T> stream);
}
```

## ZenithScopeGuard / ZenithScopeToken

```dart
class ZenithScopeGuard {
  ZenithScopeToken capture();
  void invalidate();
}
class ZenithScopeToken { bool get isCurrent; }
```

## AuthState<T> (core)

```dart
sealed class AuthState<T> {
  R when<R>({required R Function() unauthenticated,
             required R Function() authenticating,
             required R Function(T user) authenticated,
             required R Function(Object error, StackTrace st) error});
  R maybeWhen<R>({..., required R Function() orElse});
  R? whenOrNull<R>({...});
  T? get userOrNull;
  bool get isAuthenticated; bool get isUnauthenticated;
  bool get isAuthenticating; bool get hasError;
}
const AuthUnauthenticated<T>();
const AuthAuthenticating<T>();
const AuthAuthenticated<T>(T user);
const AuthError<T>(Object error, StackTrace stackTrace);
```
