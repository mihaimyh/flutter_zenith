import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zenith/flutter_zenith.dart';

abstract class ApiService {
  String get baseUrl;
}

class ProductionApiService implements ApiService {
  @override
  String get baseUrl => 'https://api.myapp.com';
}

class DevMockApiService implements ApiService {
  @override
  String get baseUrl => 'http://localhost:8080';
}

final apiServiceKey = ZenithKey<ApiService>('api_service');

void main() {
  group('ZenithEnvironment & Environment-Aware DI', () {
    test('container defaults to production environment without overrides', () {
      final container = ZenithContainer();

      expect(container.environment, ZenithEnvironment.production);

      final api = container.getOrCreate(
        apiServiceKey,
        (_) => ProductionApiService(),
      );
      expect(api.value.baseUrl, 'https://api.myapp.com');
    });

    test('container automatically applies environment-specific overrides', () {
      final devContainer = ZenithContainer(
        environment: ZenithEnvironment.development,
        environmentOverrides: {
          ZenithEnvironment.development: [
            ZenithOverride<ApiService>(apiServiceKey, (_) => DevMockApiService()),
          ],
        },
      );

      expect(devContainer.environment, ZenithEnvironment.development);

      final devApi = devContainer.getOrCreate(
        apiServiceKey,
        (_) => ProductionApiService(),
      );

      // DevMockApiService was automatically selected based on environment!
      expect(devApi.value.baseUrl, 'http://localhost:8080');
    });

    test('ignores overrides for non-matching environments', () {
      final prodContainer = ZenithContainer(
        environment: ZenithEnvironment.production,
        environmentOverrides: {
          ZenithEnvironment.development: [
            ZenithOverride<ApiService>(apiServiceKey, (_) => DevMockApiService()),
          ],
        },
      );

      final api = prodContainer.getOrCreate(
        apiServiceKey,
        (_) => ProductionApiService(),
      );

      // Fallback to production factory
      expect(api.value.baseUrl, 'https://api.myapp.com');
    });
  });
}
