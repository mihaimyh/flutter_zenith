/// `ZenithStorage` over `SharedPreferences`.
///
/// A separate entrypoint, so importing the core engine does not pull in the
/// `shared_preferences` plugin.
///
/// ```dart
/// import 'package:flutter_zenith/persistence_shared_preferences.dart';
/// ```
library;

export 'core/zenith/zenith_storage.dart';
export 'src/storage/shared_preferences_storage.dart';
