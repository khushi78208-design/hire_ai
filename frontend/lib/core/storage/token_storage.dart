import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Tokens live in the OS keychain, not SharedPreferences — a rooted device
/// or a browser extension should not be able to read a session token.
class TokenStorage {
  static const _storage = FlutterSecureStorage();

  static const _accessKey = 'access_token';
  static const _refreshKey = 'refresh_token';
  static const _roleKey = 'user_role';

  static Future<void> saveSession({
    required String accessToken,
    required String refreshToken,
    required String role,
  }) async {
    await _storage.write(key: _accessKey, value: accessToken);
    await _storage.write(key: _refreshKey, value: refreshToken);
    await _storage.write(key: _roleKey, value: role);
  }

  static Future<String?> getAccessToken() => _storage.read(key: _accessKey);
  static Future<String?> getRefreshToken() => _storage.read(key: _refreshKey);
  static Future<String?> getRole() => _storage.read(key: _roleKey);

  static Future<bool> isLoggedIn() async {
    final token = await getAccessToken();
    return token != null && token.isNotEmpty;
  }

  static Future<void> clear() async {
    await _storage.deleteAll();
  }
}