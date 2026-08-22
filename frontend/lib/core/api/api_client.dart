import 'package:dio/dio.dart';
import '../storage/token_storage.dart';

class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;

  late final Dio dio;

  /// The deployed backend. Same URL from every platform — no LAN IP, no
  /// laptop, no emulator special-casing.
  static const String baseUrl = 'https://hireai-api-e83c.onrender.com/api/v1';

  ApiClient._internal() {
    dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        // A free-tier instance spins down when idle and takes ~50s to wake,
        // so the first request of a session needs real headroom.
        connectTimeout: const Duration(seconds: 60),
        // AI endpoints call an LLM and routinely run 30-60s on top of that.
        receiveTimeout: const Duration(seconds: 120),
        sendTimeout: const Duration(seconds: 60),
        headers: {'Content-Type': 'application/json'},
        // Let us handle 4xx ourselves instead of Dio throwing.
        validateStatus: (status) => status != null && status < 500,
      ),
    );

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await TokenStorage.getAccessToken();
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
      ),
    );
  }
}
