/// Application runtime environments for `flutter_zenith`.
///
/// Use environments to conditionally configure container DI overrides and services
/// for development, staging, or production builds.
///
/// Equivalent to `IHostEnvironment` in ASP.NET Core (`IsDevelopment()`, `IsProduction()`).
enum ZenithEnvironment {
  /// Local development environment (e.g. mock APIs, verbose logging).
  development,

  /// Staging / QA testing environment (e.g. staging endpoints).
  staging,

  /// Live production environment.
  production,
}
