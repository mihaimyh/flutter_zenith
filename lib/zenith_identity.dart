/// `zenith_identity` — Enterprise multi-tenant scoping, identity &
/// policy authorization for Flutter/Dart.
///
/// Built on top of `flutter_zenith`'s core container and reactive node engine.
///
/// Sub-systems:
/// - **Scope**: Multi-tenant container runtime with 3-tier hierarchy and
///   captive dependency detection.
/// - **Identity**: Sealed auth state machine, anonymous linking, biometric
///   lock, back-channel revocation.
/// - **Storage**: Per-tenant namespaced storage and offline outbox isolation.
/// - **Authorization**: Declarative policy engine with reactive Flutter widgets.
/// - **Widgets**: Scope tunnelling, modal bridge, and declarative auth swap.
/// - **Concurrency**: Cancellation tokens with physical task abort.
/// - **Enterprise**: Cryptographic zeroization and database file isolation.
library;

// ── Core re-exports (to avoid double-import in consuming code) ───────────────
export 'package:flutter_zenith/core/zenith/zenith_key.dart';
export 'package:flutter_zenith/core/zenith/zenith_node.dart';
export 'package:flutter_zenith/core/zenith/async_value.dart';

// ── Scope ────────────────────────────────────────────────────────────────────
export 'src/scope/zenith_drainable.dart';
export 'src/scope/zenith_scope_manager.dart';
export 'src/scope/zenith_user_scope.dart';
export 'src/scope/zenith_ipc.dart';

// ── Identity ─────────────────────────────────────────────────────────────────
export 'src/identity/zenith_identity_auth_state.dart';
export 'src/identity/zenith_identity_coordinator.dart';

// ── Storage ──────────────────────────────────────────────────────────────────
export 'src/storage/zenith_partitioned_storage.dart';
export 'src/storage/zenith_outbox.dart';

// ── Authorization ─────────────────────────────────────────────────────────────
export 'src/authorization/zenith_requirement.dart';
export 'src/authorization/zenith_policy.dart';
export 'src/authorization/zenith_authorization_service.dart';
export 'src/authorization/zenith_authorize_view.dart';
export 'src/authorization/zenith_route_guard.dart';

// ── Widgets ──────────────────────────────────────────────────────────────────
export 'src/widgets/zenith_scope_provider.dart';
export 'src/widgets/zenith_scope_bridge.dart';
export 'src/widgets/zenith_auth_scope.dart';

// ── Concurrency ───────────────────────────────────────────────────────────────
export 'src/concurrency/zenith_cancellation_token.dart';
export 'src/concurrency/zenith_concurrency_runner.dart';

// ── Enterprise ────────────────────────────────────────────────────────────────
export 'src/enterprise/zenith_secure_bytes.dart';
export 'src/enterprise/zenith_database_pool.dart';
