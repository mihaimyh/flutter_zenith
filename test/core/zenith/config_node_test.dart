import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zenith/flutter_zenith.dart';

class AppConfig {
  final String apiEndpoint;
  final int maxRetries;

  const AppConfig({required this.apiEndpoint, required this.maxRetries});

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    return AppConfig(
      apiEndpoint: json['api_endpoint'] as String? ?? 'https://api.example.com',
      maxRetries: json['max_retries'] as int? ?? 3,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppConfig &&
          other.apiEndpoint == apiEndpoint &&
          other.maxRetries == maxRetries);

  @override
  int get hashCode => Object.hash(apiEndpoint, maxRetries);
}

void main() {
  group('ZenithConfigNode', () {
    const defaultConfig = AppConfig(
      apiEndpoint: 'https://api.example.com',
      maxRetries: 3,
    );

    test('initializes with default config object', () {
      final configNode = ZenithConfigNode<AppConfig>(
        key: 'app_options',
        initialConfig: defaultConfig,
        decoder: AppConfig.fromJson,
      );

      expect(configNode.value.apiEndpoint, 'https://api.example.com');
      expect(configNode.value.maxRetries, 3);
    });

    test('updateRaw parses Map and updates config when values change', () {
      final configNode = ZenithConfigNode<AppConfig>(
        key: 'app_options',
        initialConfig: defaultConfig,
        decoder: AppConfig.fromJson,
      );

      var notifications = 0;
      final sub1 = _CountingSubscriber(() => notifications++);
      configNode.subscribe(sub1);

      configNode.updateRaw({
        'api_endpoint': 'https://v2.api.example.com',
        'max_retries': 5,
      });

      expect(configNode.value.apiEndpoint, 'https://v2.api.example.com');
      expect(configNode.value.maxRetries, 5);
      expect(notifications, 1);
    });

    test('updateRaw skips notification when decoded config is identical', () {
      final configNode = ZenithConfigNode<AppConfig>(
        key: 'app_options',
        initialConfig: defaultConfig,
        decoder: AppConfig.fromJson,
      );

      var notifications = 0;
      final sub2 = _CountingSubscriber(() => notifications++);
      configNode.subscribe(sub2);

      // Same values as defaultConfig
      configNode.updateRaw({
        'api_endpoint': 'https://api.example.com',
        'max_retries': 3,
      });

      expect(notifications, 0);
    });

    test('updateRaw gracefully catches decoder exceptions and returns false', () {
      final configNode = ZenithConfigNode<AppConfig>(
        key: 'app_options',
        initialConfig: defaultConfig,
        decoder: AppConfig.fromJson,
      );

      // Malformed map causing type error
      final success = configNode.updateRaw({
        'max_retries': 'invalid_string_not_int',
      });

      expect(success, isFalse);
      // Value remains untouched
      expect(configNode.value.maxRetries, 3);
    });
  });
}

class _CountingSubscriber implements ZenithSubscriber {
  final void Function() onNotify;
  _CountingSubscriber(this.onNotify);

  @override
  void onNodeChanged(ZenithNode<dynamic> node) => onNotify();
}
