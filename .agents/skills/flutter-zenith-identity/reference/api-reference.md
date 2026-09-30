# Identity API reference

From `package:flutter_zenith/zenith_identity.dart` (`lib/src/**`).

## Scope manager

```dart
enum ZenithLifetime { singleton, scoped }

class ZenithTenantScope {
  ZenithTenantScope(String id);
  final String id;
  final ZenithContainer container;

  bool get isDisposed;
  bool get isClosing;
  bool get isDormant;
  Future<void> get disposalComplete;

  void register<T>(ZenithKey<T> key, T Function() factory, {ZenithLifetime lifetime = ZenithLifetime.scoped});
  T resolve<T>(ZenithKey<T> key);
  ZenithNode<T>? maybeNode<T>(ZenithKey<T> key);

  void markDormant();
  void markActive();

  void registerDrainable(ZenithDrainable drainable);
  void onDispose(void Function() callback);
  void onDisposeAsync(Future<void> Function() callback);

  void runGuarded(Future<void> Function() task);
  void runWithToken(Future<void> Function(ZenithCancellationToken token) task);

  void listenToInterIsolateInvalidations(String portName, {required void Function(String key) onInvalidate});

  void dispose({bool purgeZeroize = false});
  Future<void> drainAndDispose({Duration timeout = const Duration(milliseconds: 500), bool purgeZeroize = false});
  Future<void> drainOwnedScopes({required Duration timeout, required bool purgeZeroize});
}

class ZenithUserScope extends ZenithTenantScope {
  ZenithUserScope(String id);
  ZenithTenantScope getOrCreateWorkspaceScope(String workspaceId);
  bool hasWorkspaceScope(String workspaceId);
  void endWorkspaceScope(String workspaceId);
  Future<void> endWorkspaceScopeAsync(String workspaceId, {Duration timeout = const Duration(milliseconds: 500)});
}

class ZenithScopeManager {
  final ZenithTenantScope appScope; // 'ZenithTenantScope('__app__')'
  bool hasScope(String id);
  ZenithTenantScope getOrCreateScope(String id);
  ZenithUserScope getOrCreateUserScope(String id);
  void endScope(String id, {bool purgeZeroize = false});
  Future<void> endScopeAsync(String id, {Duration timeout = const Duration(milliseconds: 500), bool purgeZeroize = false});
  static Future<ZenithTenantScope> bootstrapHeadless({required String tenantId, Object? Function(String tenantId)? storageFactory});
}
```

## Draining

```dart
abstract class ZenithDrainable { Future<void> drain(); }
class ZenithDrainableCallback implements ZenithDrainable {
  ZenithDrainableCallback(Future<void> Function() callback);
}
```

## Identity coordinator

```dart
enum RevocationReason { sessionInvalidatedByAdmin, tokenExpired, securityViolation }

class ZenithMigrationException implements Exception {
  ZenithMigrationException(Object cause, StackTrace stackTrace);
}

class ZenithIdentityCoordinator {
  ZenithAuthState get state;
  ZenithTenantScope? get currentScope;
  bool hasScope(String id);

  void addListener(void Function() listener);
  void removeListener(void Function() listener);

  Future<void> signIn<T>(T session, {String? tenantId});
  Future<void> signInAnonymously({required String anonId});
  Future<void> signOut();
  Future<void> upgradeAnonymousAccount<T>({
    required T newSession,
    String? tenantId,
    required Future<void> Function(ZenithContainer fromContainer, ZenithContainer toContainer) onMigrate,
  });

  void lockSession();
  Future<void> unlockSession();

  void onSecurityRevocation(void Function(RevocationReason reason) listener);
  Future<void> ingestRemoteRevocation({required String tenantId, required RevocationReason reason});
}

sealed class ZenithAuthState {}
final class AuthUnauthenticated extends ZenithAuthState {}
final class AuthAnonymous extends ZenithAuthState { final String anonId; }
final class AuthAuthenticated<T> extends ZenithAuthState { final T session; }
final class AuthMigrating extends ZenithAuthState { final String fromId; final String toId; }
final class AuthLocked<T> extends ZenithAuthState { final T session; }
```

## Tenant storage

```dart
abstract class StorageDriver {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}
class InMemoryStorageDriver implements StorageDriver {
  Future<String?> rawRead(String key); // bypasses namespacing (tests)
}

class ZenithPartitionedStorage {
  ZenithPartitionedStorage({required StorageDriver driver, required String tenantId});
  final StorageDriver driver;
  final String tenantId;
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}
```

## Outbox

```dart
class OutboxMutation {
  OutboxMutation({String? id, required String tenantId, required String action,
                  required Map<String, dynamic> payload, int maxRetries = 3,
                  int retryCount = 0, Object? lastError,
                  DateTime? lastAttemptedAt, DateTime? nextRetryAfter});
  final String id;
  final String tenantId;
  final String action;
  final Map<String, dynamic> payload;
  final int maxRetries;
  int retryCount;
  Object? lastError;
  DateTime? lastAttemptedAt;
  DateTime? nextRetryAfter;
  bool isEligibleForRetry([DateTime? now]);
}

class ZenithOutboxEngine {
  List<OutboxMutation> get deadLetterQueue;
  void enqueue({required String tenantId, required String action, required Map<String, dynamic> payload, int maxRetries = 3});
  void setActiveTenant(String? tenantId);
  int pendingCount(String tenantId);
  int deadLetterCount(String tenantId);
  Future<void> flush(
    Future<void> Function(OutboxMutation mutation) dispatcher, {
    void Function(OutboxMutation mutation, Object error)? onMutationError,
    bool ignoreBackoff = false,
    Duration baseBackoff = const Duration(milliseconds: 100),
    Duration maxBackoff = const Duration(seconds: 60),
  });
}
```

## Authorization

```dart
class UserSecurityContext {
  const UserSecurityContext({bool isAuthenticated = false,
                             Map<String, dynamic> claims = const {},
                             double consumedBandwidthGb = 0,
                             List<String> roles = const []});
  List<String> get entitlements; // from claims['entitlement']
}

abstract class ZenithRequirement { bool evaluate(UserSecurityContext context); }
class RequireAuthenticatedUser implements ZenithRequirement { const RequireAuthenticatedUser(); }
class RequireEntitlement implements ZenithRequirement { const RequireEntitlement(String entitlement); }
class RequireRole implements ZenithRequirement { const RequireRole(String role); }
class RequireMaxMonthlyBandwidth implements ZenithRequirement { const RequireMaxMonthlyBandwidth({required double quotaGb}); }

class ZenithPolicy {
  const ZenithPolicy({required String name,
                      List<ZenithRequirement>? requirements,
                      bool Function(PolicyRef ref)? evaluate,
                      AsyncValue<bool> Function(PolicyRef ref)? evaluateAsync});
}
class PolicyRef { T watch<T>(ZenithNode<T> node); }

class AuthorizationResult {
  const AuthorizationResult({required bool isAuthorized, String? reason});
  final bool isAuthorized;
  final String? reason;
}
class ZenithAuthorizationService {
  const ZenithAuthorizationService();
  AuthorizationResult evaluate(UserSecurityContext context, ZenithPolicy policy);
  AsyncValue<bool> evaluateState(UserSecurityContext context, ZenithPolicy policy, {PolicyRef? ref});
}
class ZenithRouteGuard {
  static String? evaluate({required UserSecurityContext context,
                           required ZenithPolicy policy,
                           required ZenithAuthorizationService authService,
                           required String deniedRedirectPath});
}

class ZenithAuthorizeView extends StatefulWidget {
  const ZenithAuthorizeView({required ZenithPolicy policy,
                             required Widget Function(BuildContext) authorized,
                             required Widget Function(BuildContext, AuthorizationResult) notAuthorized,
                             Widget Function(BuildContext)? authorizing,
                             UserSecurityContext securityContext = const UserSecurityContext()});
  factory ZenithAuthorizeView.hidden({required ZenithPolicy policy, UserSecurityContext securityContext, required Widget Function(BuildContext) authorized});
  factory ZenithAuthorizeView.locked({required ZenithPolicy policy, UserSecurityContext securityContext, required Widget Function(BuildContext) authorized, Widget Function(BuildContext, AuthorizationResult)? notAuthorized});
}
```

## Widgets

```dart
class ZenithScopeProvider extends InheritedWidget {
  const ZenithScopeProvider({required ZenithTenantScope scope, required Widget child, Key? key});
  static ZenithTenantScope of(BuildContext context);
  static ZenithTenantScope? maybeOf(BuildContext context);
}
extension ZenithScopeContextX on BuildContext {
  ZenithTenantScope get zenithScope;
  T zenith<T>(ZenithKey<T> key);
}

class ZenithAuthScope extends StatefulWidget {
  const ZenithAuthScope({required ZenithIdentityCoordinator coordinator,
                         required Widget Function(BuildContext, ZenithTenantScope) authenticatedBuilder,
                         required Widget Function(BuildContext) unauthenticatedBuilder,
                         Widget Function(BuildContext)? lockedBuilder});
}

extension ZenithScopeBridgeX on BuildContext {
  Future<T?> zenithShowModalBottomSheet<T>({
    required Widget Function(BuildContext sheetContext) builder,
    bool isScrollControlled = false,
    bool useRootNavigator = false,
    bool isDismissible = true,
    Color? backgroundColor,
    ShapeBorder? shape,
  });
}
```

## Cancellation

```dart
class ZenithCancellationToken {
  bool get isCancelled;
  void onCancel(void Function() callback);
  void cancel();
}

class ZenithConcurrencyRunner {
  void runAsyncRestartable(Future<void> Function(ZenithCancellationToken token) task);
  void cancelCurrent();
}
```

## Enterprise

```dart
abstract class ZenithDatabaseHandle {
  String get filePath;
  bool get isOpen;
  Future<void> close();
}
class ZenithDatabasePool {
  ZenithDatabasePool({required String baseDir, required Future<ZenithDatabaseHandle> Function(String path) openHandle});
  Future<ZenithDatabaseHandle> acquireConnection(String tenantId, {ZenithTenantScope? scope});
  void bindScope(ZenithTenantScope scope);
  Future<void> releaseConnection(String tenantId);
  Future<void> disposeAll();
}
class InMemoryDatabasePool extends ZenithDatabasePool {
  InMemoryDatabasePool({required String baseDir});
}

class ZenithSecureBytes implements Zeroizable {
  ZenithSecureBytes(Uint8List rawBytes);
  Uint8List get bytes;
  bool get isZeroized;
  void zeroize();
}
```

## IPC

```dart
class ZenithInvalidateMessage {
  const ZenithInvalidateMessage({required String tenantId, required String nodeKey});
}
// Register via scope.listenToInterIsolateInvalidations(portName, onInvalidate: (key) {});
```
