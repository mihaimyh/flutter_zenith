# App utilities API reference

From `persisted_node.dart`, `zenith_storage.dart`, `zenith_config.dart`, `zenith_feature.dart`, `zenith_validator.dart`, `zenith_mediator.dart`, `zenith_resilience.dart`, `zenith_logger.dart`, `zenith_observer.dart`, `zenith_middleware.dart`.

## Persistence

```dart
abstract class ZenithStorage {
  String? read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
  Future<void> clear();
}
class InMemoryStorage implements ZenithStorage {}

class PersistedNode<T> extends ZenithNode<T> {
  PersistedNode({
    required String key,
    required T defaultValue,
    required ZenithStorage storage,
    required String Function(T value) toStorage,
    required T Function(String raw) fromStorage,
  });
  static PersistedNode<String> string({required String key, required String defaultValue, required ZenithStorage storage});
  static PersistedNode<int>    integer({required String key, required int defaultValue, required ZenithStorage storage});
  static PersistedNode<bool>   boolean({required String key, required bool defaultValue, required ZenithStorage storage});

  final String key;
  final ZenithStorage storage;
  final String Function(T value) toStorage;
  final T Function(String raw) fromStorage;
  Object? get persistenceError;
  Future<void> flush();
}
```

## Config

```dart
class ZenithConfigNode<T> extends ZenithNode<T> {
  ZenithConfigNode({required String key, required T initialConfig, required T Function(Map<String, dynamic> json) decoder});
  final String key;
  final T Function(Map<String, dynamic> json) decoder;
  bool updateRaw(Map<String, dynamic> json);
}
```

## Feature flags

```dart
class ZenithFeature {
  const ZenithFeature(String key, {bool defaultValue = false, String? name});
  final String key; final bool defaultValue; final String? name;
  static bool percentageRollout(int percentage, {required String featureKey, required String userId});
}
class FeatureNode extends ZenithNode<bool> {
  FeatureNode(ZenithFeature feature, bool initialValue);
  final ZenithFeature feature;
  void toggle();
}
class ZenithFeatureBuilder extends StatelessWidget {
  const ZenithFeatureBuilder({required FeatureNode featureNode,
                              required WidgetBuilder enabled,
                              WidgetBuilder? disabled});
}
```

## Validation

```dart
class ValidationError { const ValidationError({required String propertyName, required String message}); }
class ValidationResult {
  const ValidationResult(List<ValidationError> errors);
  final List<ValidationError> errors;
  bool get isValid;
  List<String> errorsFor(String propertyName);
}
class PropertyRuleBuilder<T, V> {
  PropertyRuleBuilder(V Function(T model) selector, String propertyName);
  PropertyRuleBuilder<T, V> notEmpty([String? customMessage]);
  PropertyRuleBuilder<T, V> email([String? customMessage]);
  PropertyRuleBuilder<T, V> minLength(int min, [String? customMessage]);
  PropertyRuleBuilder<T, V> greaterThan(num target, [String? customMessage]);
  PropertyRuleBuilder<T, V> must(bool Function(V value) predicate, String errorMessage);
}
abstract class ZenithValidator<T> {
  PropertyRuleBuilder<T, V> ruleFor<V>(V Function(T model) selector, String propertyName);
  ValidationResult validate(T model);
}
class ZenithValidatedNode<T> extends ZenithNode<T> {
  ZenithValidatedNode(T model, {required ZenithValidator<T> validator});
  bool get isValid;
  ValidationResult get validationResult;
  List<String> errorsFor(String propertyName);
}
```

## Mediator

```dart
abstract class ZenithCommand<R> { const ZenithCommand(); }
abstract class ZenithEvent { const ZenithEvent(); }
typedef ZenithCommandHandler<C extends ZenithCommand<R>, R> = FutureOr<R> Function(ZenithRef ref, C command);
typedef ZenithEventHandler<E extends ZenithEvent> = FutureOr<void> Function(ZenithRef ref, E event);

abstract class ZenithPipelineBehavior {
  Future<R> handle<R>(ZenithRef ref, ZenithCommand<R> command, Future<R> Function() next);
}

class ZenithMediator {
  ZenithMediator(ZenithContainer container);
  static const int maxCallDepth = 10;
  void registerCommandHandler<C extends ZenithCommand<R>, R>(ZenithCommandHandler<C, R> handler);
  void registerEventHandler<E extends ZenithEvent>(ZenithEventHandler<E> handler);
  void addBehavior(ZenithPipelineBehavior behavior);
  Future<R> send<R>(ZenithCommand<R> command);
  Future<void> publish<E extends ZenithEvent>(E event);
}

extension ZenithMediatorContainerX on ZenithContainer { ZenithMediator get mediator; }
extension ZenithMediatorRefX on ZenithRef { ZenithMediator get mediator; }
```

## Resilience

```dart
enum CircuitState { closed, open, halfOpen }

class ZenithResiliencePipeline {
  CircuitState get circuitState;
  ZenithResiliencePipeline withRetry({int maxAttempts = 3, Duration initialDelay = const Duration(milliseconds: 100), double backoffFactor = 2.0, bool enableJitter = true});
  ZenithResiliencePipeline withCircuitBreaker({int failureThreshold = 5, Duration resetTimeout = const Duration(seconds: 30)});
  ZenithResiliencePipeline withRateLimiter({required int maxRequests, required Duration window});
  Future<T> execute<T>(Future<T> Function() task);
}

extension ZenithResilienceRefX on ZenithRef {
  Future<void> runResilient<T>(ZenithNode<AsyncValue<T>> node, Future<T> Function() task, {required ZenithResiliencePipeline pipeline});
}
```

## Logging

```dart
enum ZenithLogLevel { verbose, debug, info, warning, error, fatal }

class ZenithLogEvent {
  ZenithLogEvent({required ZenithLogLevel level, required String template,
                  required Map<String, dynamic> properties, required DateTime timestamp,
                  Object? error, StackTrace? stackTrace});
  String get formattedMessage;
}
abstract class ZenithLogSink { void emit(ZenithLogEvent event); }
class ConsoleSink implements ZenithLogSink {}
class MemoryRingBufferSink implements ZenithLogSink {
  MemoryRingBufferSink({int maxCapacity = 100});
  List<ZenithLogEvent> get logs;
  void clear();
}
class ZenithLogger {
  ZenithLogger({List<ZenithLogSink>? sinks});
  final List<ZenithLogSink> sinks;
  void info(String template, [Map<String, dynamic>? properties, Object? error, StackTrace? stackTrace]);
  void warning(String template, [Map<String, dynamic>? properties, Object? error, StackTrace? stackTrace]);
  void error(String template, [Map<String, dynamic>? properties, Object? error, StackTrace? stackTrace]);
  void log(ZenithLogLevel level, String template, [Map<String, dynamic>? properties, Object? error, StackTrace? stackTrace]);
}
extension ZenithLoggerContainerX on ZenithContainer { ZenithLogger get logger; }
extension ZenithLoggerRefX on ZenithRef { ZenithLogger get logger; }
```

## Observers

```dart
abstract class ZenithObserver {
  void onNodeCreated(ZenithContainer container, Object key, ZenithNode<dynamic> node) {}
  void onNodeMutated(ZenithNode<dynamic> node, dynamic oldValue, dynamic newValue) {}
  void onNodeDisposed(ZenithNode<dynamic> node) {}
  void onContainerCreated(ZenithContainer container) {}
  void onContainerDisposed(ZenithContainer container) {}
}
class ZenithLogObserver extends ZenithObserver {}
class Zenith {
  static ZenithObserver? observer;
  static void Function(String message)? onDebugPrint;
}
```

## Middleware

```dart
abstract class ZenithMiddleware<T> {
  T? onWillSet(ZenithNode<T> node, T currentValue, T newValue) => newValue; // null cancels
  void onDidSet(ZenithNode<T> node, T value) {}
}
```
