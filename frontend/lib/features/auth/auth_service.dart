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
    try {
      final refresh = await TokenStorage.getRefreshToken();
      await _dio.post('/auth/logout', data: {'refreshToken': refresh});
    } catch (_) {
      // Even if the server call fails, clear locally — the user asked to leave.
    }
    await TokenStorage.clear();
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

    // Backend sends every error in the same shape, so one path handles all.
    final message = (body is Map && body['error'] is Map)
        ? body['error']['message'] as String?
        : null;

    return AuthResult(
      success: false,
      error: message ?? 'Something went wrong. Try again.',
    );
  }

  static String _networkError(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.connectionError) {
      return 'Cannot reach the server. Is the backend running?';
    }
    return 'Network error. Check your connection.';
  }
}
