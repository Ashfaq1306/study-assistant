import 'package:dio/dio.dart';

/// A failure the UI can show. [code] mirrors the server's error codes
/// (e.g. `OTP_INVALID`); [fieldErrors] maps form fields to messages.
class ApiException implements Exception {
  const ApiException({
    required this.code,
    required this.message,
    this.statusCode,
    this.fieldErrors = const {},
    this.details = const {},
  });

  static const network = 'NETWORK';
  static const unknown = 'UNKNOWN';

  final String code;
  final String message;
  final int? statusCode;
  final Map<String, String> fieldErrors;
  final Map<String, Object?> details;

  bool get isNetwork => code == network;

  factory ApiException.fromDio(DioException error) {
    final data = error.response?.data;
    if (data is Map && data['error'] is Map) {
      final body = Map<String, Object?>.from(data['error'] as Map);
      final details = body['details'] is Map
          ? Map<String, Object?>.from(body['details'] as Map)
          : const <String, Object?>{};
      return ApiException(
        code: body['code'] as String? ?? unknown,
        message: body['message'] as String? ?? 'Something went wrong.',
        statusCode: error.response?.statusCode,
        fieldErrors: _parseFields(details['fields']),
        details: details,
      );
    }

    return switch (error.type) {
      DioExceptionType.connectionError ||
      DioExceptionType.connectionTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.sendTimeout => const ApiException(
        code: network,
        message: "Can't reach Study Assistant. Check your internet and try again.",
      ),
      _ => ApiException(
        code: unknown,
        message: 'Something went wrong. Please try again.',
        statusCode: error.response?.statusCode,
      ),
    };
  }

  /// Keeps the first message per field; that is what a form shows.
  static Map<String, String> _parseFields(Object? fields) {
    if (fields is! Map) return const {};
    return {
      for (final entry in fields.entries)
        if (entry.value is List && (entry.value as List).isNotEmpty)
          entry.key.toString(): (entry.value as List).first.toString(),
    };
  }

  @override
  String toString() => 'ApiException($code, $statusCode): $message';
}
