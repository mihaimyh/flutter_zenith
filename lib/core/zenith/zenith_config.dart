import 'zenith_node.dart';

/// A strongly-typed configuration node that parses dynamic JSON/Map payloads
/// (e.g. from Remote Config, local assets, or feature flags) into type [T].
///
/// Equivalent to the Options Pattern (`IOptionsMonitor<T>`) in ASP.NET Core.
///
/// ```dart
/// final appConfigNode = ZenithConfigNode<AppConfig>(
///   key: 'app_options',
///   initialConfig: const AppConfig(),
///   decoder: AppConfig.fromJson,
/// );

/// appConfigNode.updateRaw({'api_endpoint': 'https://v2.api.com'});
/// ```
class ZenithConfigNode<T> extends ZenithNode<T> {
  /// The key used for identifying this configuration node.
  final String key;

  /// The decoder callback parsing a [Map<String, dynamic>] into [T].
  final T Function(Map<String, dynamic> json) decoder;

  /// Creates a [ZenithConfigNode] with initial [initialConfig] and [decoder].
  ZenithConfigNode({
    required this.key,
    required T initialConfig,
    required this.decoder,
  }) : super(initialConfig);

  /// Attempts to parse [json] into [T] using [decoder] and updates the node value.
  ///
  /// - Returns `true` if the config was successfully decoded and updated.
  /// - Returns `false` if decoding throws an exception (value remains untouched).
  bool updateRaw(Map<String, dynamic> json) {
    try {
      final newConfig = decoder(json);
      set(newConfig);
      return true;
    } catch (_) {
      return false;
    }
  }
}
