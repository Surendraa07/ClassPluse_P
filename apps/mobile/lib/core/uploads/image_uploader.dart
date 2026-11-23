import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../api/api_client.dart';
import '../providers.dart';

enum UploadKind { avatar, slide }

/// Signed upload to Cloudinary: asks our server for a signature, then sends the file straight
/// to Cloudinary (our API token is never sent there). Returns the image's https URL, which the
/// caller then saves on the slide or profile; the server checks it again at that point.
class ImageUploader {
  ImageUploader(this._api, {Dio? dio}) : _dio = dio ?? Dio(BaseOptions(sendTimeout: const Duration(seconds: 60), receiveTimeout: const Duration(seconds: 30)));

  final ApiClient _api;
  final Dio _dio;

  static const allowedExtensions = {'jpg', 'jpeg', 'png', 'webp'};

  Future<String> upload(
    UploadKind kind, {
    required List<int> bytes,
    required String filename,
    void Function(double progress)? onProgress,
  }) async {
    final ext = filename.contains('.') ? filename.split('.').last.toLowerCase() : '';
    if (!allowedExtensions.contains(ext)) {
      throw ApiException('INVALID_IMAGE', 'Choose a JPG, PNG or WebP image.');
    }

    final sig = await _api.post<Map<String, dynamic>>('/uploads/signature', {'kind': kind.name});
    final maxBytes = (sig['maxBytes'] as num?)?.toInt() ?? 5 * 1024 * 1024;
    if (bytes.length > maxBytes) {
      throw ApiException('INVALID_IMAGE', 'That image is too large (max ${maxBytes ~/ (1024 * 1024)} MB).');
    }

    final params = (sig['params'] as Map).cast<String, Object?>();
    final form = FormData.fromMap({
      for (final e in params.entries) e.key: e.value.toString(),
      'api_key': sig['apiKey'],
      'signature': sig['signature'],
      'file': MultipartFile.fromBytes(bytes, filename: filename),
    });

    try {
      final res = await _dio.post<Map<String, dynamic>>(
        sig['uploadUrl'] as String,
        data: form,
        onSendProgress: onProgress == null ? null : (sent, total) => total > 0 ? onProgress(sent / total) : null,
      );
      final url = res.data?['secure_url'];
      if (url is! String) throw ApiException('UPLOAD_FAILED', 'Upload failed. Please try again.');
      return url;
    } on DioException catch (e) {
      final data = e.response?.data;
      final message = data is Map && data['error'] is Map ? (data['error'] as Map)['message']?.toString() : null;
      if (e.response == null) {
        throw ApiException('NETWORK', "Couldn't upload the image. Check your connection and try again.");
      }
      throw ApiException('UPLOAD_FAILED', message ?? 'Upload failed. Please try again.', status: e.response?.statusCode);
    }
  }
}

final imageUploaderProvider = Provider<ImageUploader>((ref) => ImageUploader(ref.watch(apiClientProvider)));

/// Asks the user for a photo (gallery or camera), already scaled down on the device.
/// Returns null if they cancel.
Future<XFile?> pickImage(ImageSource source, {double maxSide = 1600}) {
  return ImagePicker().pickImage(source: source, maxWidth: maxSide, maxHeight: maxSide, imageQuality: 85);
}
