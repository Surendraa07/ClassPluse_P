import 'package:dio/dio.dart';

import '../config.dart';

/// Error with the server's `{ error: { code, message, details } }` shape, or a client-side code
/// (`NETWORK`, `TIMEOUT`, `UNKNOWN`).
class ApiException implements Exception {
  ApiException(this.code, this.message, {this.status, this.details});

  final String code;
  final String message;
  final int? status;
  final Object? details;

  bool get isNetwork => code == 'NETWORK' || code == 'TIMEOUT';
  bool get isUnauthorized => status == 401;

  /// Field-level messages from a VALIDATION_ERROR, keyed by path ("email", "options.0.label").
  Map<String, String> get fieldErrors {
    final d = details;
    if (d is! List) return const {};
    return {
      for (final item in d)
        if (item is Map && item['path'] is String && item['message'] is String) item['path'] as String: item['message'] as String,
    };
  }

  @override
  String toString() => 'ApiException($code, $message)';
}

typedef TokenGetter = String? Function();

/// Thin dio wrapper: base URL, JSON, bearer token, and error mapping to [ApiException].
class ApiClient {
  ApiClient({required TokenGetter token, void Function()? onUnauthorized, Dio? dio, String? baseUrl})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: baseUrl ?? AppConfig.apiBase,
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 12),
              sendTimeout: const Duration(seconds: 12),
              contentType: Headers.jsonContentType,
              responseType: ResponseType.json,
            )) {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        final t = token();
        if (t != null && !options.headers.containsKey('Authorization')) {
          options.headers['Authorization'] = 'Bearer $t';
        }
        handler.next(options);
      },
      onError: (e, handler) {
        if (e.response?.statusCode == 401 && token() != null) onUnauthorized?.call();
        handler.next(e);
      },
    ));
  }

  final Dio _dio;

  Future<T> get<T>(String path) => _send(() => _dio.get<T>(path));
  Future<T> post<T>(String path, [Object? body]) => _send(() => _dio.post<T>(path, data: body));
  Future<T> patch<T>(String path, [Object? body]) => _send(() => _dio.patch<T>(path, data: body));
  Future<void> delete(String path) => _send(() => _dio.delete<dynamic>(path));

  Future<T> _send<T>(Future<Response<T>> Function() call) async {
    try {
      final res = await call();
      return res.data as T;
    } on DioException catch (e) {
      throw _map(e);
    }
  }

  static ApiException _map(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return ApiException('TIMEOUT', 'The server took too long to respond. Check your connection and try again.');
      case DioExceptionType.connectionError:
        return ApiException('NETWORK', "Can't reach the server. Check your internet connection.");
      default:
        break;
    }
    final res = e.response;
    final data = res?.data;
    if (data is Map && data['error'] is Map) {
      final err = data['error'] as Map;
      return ApiException(
        (err['code'] ?? 'UNKNOWN').toString(),
        (err['message'] ?? 'Something went wrong').toString(),
        status: res?.statusCode,
        details: err['details'],
      );
    }
    if (res == null) return ApiException('NETWORK', "Can't reach the server. Check your internet connection.");
    return ApiException('UNKNOWN', 'Something went wrong (${res.statusCode}).', status: res.statusCode);
  }
}
