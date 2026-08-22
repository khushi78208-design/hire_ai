import 'package:dio/dio.dart';
import '../../core/api/api_client.dart';
import '../../core/storage/token_storage.dart';

class AuthResult {
  final bool success;
  final String? error;
  final String? role;

  AuthResult({required this.success, this.error, this.role});
}

class AuthService {
  static final Dio _dio = ApiClient().dio;

  static Future<AuthResult> register({
    required String email,
    required String password,
    required String fullName,
    required String role,
  }) async {
    try {
      final res = await _dio.post(
        '/auth/register',
        data: {
          'email': email,
          'password': password,
          'full_name': fullName,
          'role': role,
        },
      );

      return _handleAuthResponse(res);
    } on DioException catch (e) {
      return AuthResult(success: false, error: _networkError(e));
    }
  }

  static Future<AuthResult> login({
    required String email,
    required String password,
  }) async {
    try {
      final res = await _dio.post(
        '/auth/login',
        data: {'email': email, 'password': password},
      );

      return _handleAuthResponse(res);
    } on DioException catch (e) {
      return AuthResult(success: false, error: _networkError(e));
    }
  }

  static Future<void> logout() async {
    final refresh = await TokenStorage.getRefreshToken();
    // Clear first — a failed network call must never leave the user
    // half-logged-in.
    await TokenStorage.clear();
    try {
      await _dio.post('/auth/logout', data: {'refreshToken': refresh});
    } catch (_) {}
  }

  /// Storage can go stale after a logout that half-failed. The server is
  /// the only authority on who you actually are.
  static Future<String?> currentRole() async {
    try {
      final res = await _dio.get('/auth/me');
      if (res.data?['success'] == true) {
        return res.data['data']['user']['role'] as String?;
      }
    } catch (_) {}
    return null;
  }

  static Future<String?> currentName() async {
    try {
      final res = await _dio.get('/auth/me');
      if (res.data?['success'] == true) {
        return res.data['data']['user']['full_name'] as String?;
      }
    } catch (_) {}
    return null;
  }

  static Future<AuthResult> _handleAuthResponse(Response res) async {
    final body = res.data;

    if (body is Map && body['success'] == true) {
      final data = body['data'];
      final user = data['user'];

      await TokenStorage.saveSession(
        accessToken: data['accessToken'],
        refreshToken: data['refreshToken'],
        role: user['role'],
      );

      return AuthResult(success: true, role: user['role']);
    }

    String? message;
    if (body is Map && body['error'] is Map) {
      final err = body['error'];
      final details = err['details'];

      // Validation errors carry the useful text in details[].message —
      // err.message is just "Validation failed", which tells the user nothing.
      if (details is List && details.isNotEmpty) {
        message = details.map((d) => d['message']).join('\n');
      } else {
        message = err['message'] as String?;
      }
    }

    return AuthResult(
      success: false,
      error: message ?? 'Something went wrong. Try again.',
    );
  }

  static String _networkError(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.connectionError) {
      return 'Cannot reach the server. It may be waking up — try again.';
    }
    return 'Network error. Check your connection.';
  }
}
