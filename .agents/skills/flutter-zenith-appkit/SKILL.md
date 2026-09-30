---
name: flutter-zenith-appkit
description: Application-layer utilities in flutter_zenith — persistence, configuration, feature flags, validation, mediator (commands/events), resilience pipeline, structured logging, observers, and node middleware. Use when persisting state with PersistedNode/ZenithStorage, decoding config, gating features, validating forms, wiring ZenithMediator commands, adding retry/circuit-breaker/rate-limit, emitting ZenithLogger events, or observing node mutations.
license: MIT
---

# flutter_zenith — application utilities

Read the parent `flutter-zenith` skill first. These are optional core-side building blocks.

## Persistence

```dart
final storage = InMemoryStorage(); // implement ZenithStorage for real backends

final theme = PersistedNode.string(key: 'theme', defaultValue: 'system', storage: storage);
theme.value = 'dark';
await theme.flush();                 // await this node's latest accepted write
theme.persistenceError;              // latest write/serialize failure (cleared on success)
theme.dispose();
```

Helpers: `PersistedNode.string`, `.integer`, `.boolean`; or the full constructor with `toStorage`/`fromStorage` callbacks.

`ZenithStorage`:

```dart
abstract class ZenithStorage {
  String? read(String key);                   // SYNCHRONOUS
  Future<void> write(String key, String value);
  Future<void> delete(String key);
  Future<void> clear();
}
```

- Reads are synchronous, so async backends (Hive/SQLite/secure storage) need preloading/caching or a separate hydration flow.
- Accepted writes are serialized across nodes sharing the same backend instance and key.
- Disposal does **not** cancel accepted writes. `flush()` before ending a scope when durability matters.
- Identity's `StorageDriver` is a separate, fully async interface — not interchangeable (see `flutter-zenith-identity`).

## Configuration

```dart
class AppConfig { const AppConfig(); factory AppConfig.fromJson(Map<String, dynamic> j) => const AppConfig(); }

final config = ZenithConfigNode<AppConfig>(
  key: 'app_options',
  initialConfig: const AppConfig(),
  decoder: AppConfig.fromJson,
);
config.updateRaw({'api_endpoint': 'https://v2.api.com'}); // true if decoded; false on failure (value untouched)
```

## Feature flags

```dart
const newCheckout = ZenithFeature('new_checkout', defaultValue: false);
final flag = FeatureNode(newCheckout, false);
flag.toggle();

ZenithFeatureBuilder(
  featureNode: flag,
  enabled: (ctx) => const NewCheckoutScreen(),
  disabled: (ctx) => const LegacyCheckoutScreen(), // defaults to SizedBox.shrink()
);

ZenithFeature.percentageRollout(25, featureKey: 'new_checkout', userId: 'u1'); // deterministic per user
```

## Validation

```dart
class SignupValidator extends ZenithValidator<SignupForm> {
  SignupValidator() {
    ruleFor((f) => f.email, 'email').notEmpty().email();
    ruleFor((f) => f.age, 'age').greaterThan(17);
    ruleFor((f) => f.handle, 'handle').minLength(3)
        .must((h) => !h.contains(' '), 'No spaces allowed.');
  }
}

final result = SignupValidator().validate(form);
result.isValid;
result.errorsFor('email'); // List<String>

// Or a self-validating node:
final node = ZenithValidatedNode(form, validator: SignupValidator());
node.isValid; node.validationResult; node.errorsFor('email');
```

Built-in rules: `notEmpty`, `email`, `minLength`, `greaterThan`, `must(predicate, message)`. Everything else goes through `must`.

## Mediator (commands / events)

```dart
class PlaceOrder extends ZenithCommand<Receipt> { const PlaceOrder(this.items); final List<Item> items; }
class OrderPlaced extends ZenithEvent { const OrderPlaced(this.orderId); final String orderId; }

final mediator = container.mediator;                 // or ref.mediator (auto-created, container-scoped)

mediator.registerCommandHandler<PlaceOrder, Receipt>((ref, cmd) async => api.place(cmd.items));
mediator.registerEventHandler<OrderPlaced>((ref, e) => analytics.track(e.orderId));
mediator.addBehavior(LoggingBehavior());             // ZenithPipelineBehavior wraps execution

final receipt = await mediator.send(PlaceOrder(items));
await mediator.publish(OrderPlaced(receipt.id));
```

- One handler per command type (re-registering replaces). Multiple event handlers run **sequentially**.
- Event handler failures are debug-logged and do **not** stop the others.
- Command recursion depth limit is `ZenithMediator.maxCallDepth` (10) — exceeding it throws `StateError`.
- No handler registered → `send` throws `StateError`.

## Resilience

```dart
final pipeline = ZenithResiliencePipeline()
    .withRetry(maxAttempts: 3, initialDelay: Duration(milliseconds: 100), backoffFactor: 2.0, enableJitter: true)
    .withCircuitBreaker(failureThreshold: 5, resetTimeout: Duration(seconds: 30))
    .withRateLimiter(maxRequests: 20, window: Duration(seconds: 1));

final data = await pipeline.execute(() => api.fetch());
pipeline.circuitState; // closed / open / halfOpen

// Or write an AsyncValue node directly:
await ref.runResilient(node, () => api.fetch(), pipeline: pipeline);
```

- Rate limiting counts **admitted executions**; retries happen inside one execution.
- Circuit-open and rate-limit-exceeded throw `StateError`.
- The limiter uses monotonic elapsed time (immune to wall-clock changes).

## Logging

```dart
final logger = ZenithLogger(sinks: [ConsoleSink(), MemoryRingBufferSink(maxCapacity: 200)]);
logger.info('User {userId} logged in', {'userId': '123'});
logger.warning('...'); logger.error('...', {'token': secret}, error, stack);
logger.log(ZenithLogLevel.fatal, 'template {key}', {'key': v});

container.logger; // or ref.logger — container-scoped default
MemoryRingBufferSink().logs; // oldest-first unmodifiable view
```

- Redaction masks recognized top-level property names (password, token, auth_token, secret, creditcard, ssn, auth_header) by substring match on the normalized key.
- Redaction is **not** recursive: nested maps, message text and exception objects are not sanitized.
- Sink exceptions are swallowed.

## Observers and debug output

```dart
void main() {
  Zenith.observer = ZenithLogObserver();                 // debug-only logging of node/container events
  Zenith.onDebugPrint = (msg) => debugPrint(msg);        // Zenith's own warnings (e.g. disposed-node writes)
  runApp(const App());
}
```

`ZenithObserver` callbacks: `onNodeCreated`, `onNodeMutated`, `onNodeDisposed`, `onContainerCreated`, `onContainerDisposed`. Mutations are dispatched; the lifecycle observer methods are declared but **not currently dispatched**.

## Middleware

See `flutter-zenith-state` for `ZenithMiddleware` write interception (`onWillSet` returns a transformed value or `null` to cancel; `onDidSet` after notification).

## Recipes

**Persisted settings controller** — wrap settings in `PersistedNode`, `flush()` on app pause/logout.

**Remote config** — `ZenithConfigNode.updateRaw(json)`, react with `ZenithBuilder`.

**Command bus** — register handlers once in `main`, call `container.mediator.send(...)` from controllers.

## Gotchas

1. `ZenithStorage.read` is synchronous; preload async backends.
2. `flush()` only observes that node's latest accepted write; disposal doesn't cancel accepted writes.
3. Mediator event errors are swallowed (debug-log only).
4. Logging redaction is top-level only — don't log secrets inside nested objects.
5. Resilience rejections are `StateError`, not custom exception types.
6. `ZenithFeature.percentageRollout` needs a stable `userId` to stay deterministic.

## Reference

- [reference/api-reference.md](reference/api-reference.md) — exact signatures for all utilities.
