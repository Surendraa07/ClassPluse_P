import 'dart:convert';
import 'dart:typed_data';

import 'package:classpluse/core/api/api_client.dart';
import 'package:classpluse/core/uploads/image_uploader.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records requests and answers them from [handler].
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.handler);
  final ResponseBody Function(RequestOptions o, String body) handler;
  final requests = <({RequestOptions options, String body})>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final bytes = <int>[];
    if (requestStream != null) {
      await for (final chunk in requestStream) {
        bytes.addAll(chunk);
      }
    }
    final body = latin1.decode(bytes);
    requests.add((options: options, body: body));
    return handler(options, body);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody json(Object body, [int status = 200]) =>
    ResponseBody.fromString(jsonEncode(body), status, headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});

const signature = {
  'uploadUrl': 'https://api.cloudinary.com/v1_1/test-cloud/image/upload',
  'apiKey': '123',
  'signature': 'abc123',
  'params': {'allowed_formats': 'jpg,jpeg,png,webp', 'folder': 'classpluse/slides/l1', 'timestamp': 1700000000, 'transformation': 'c_limit,w_1600,h_1600'},
  'maxBytes': 1000,
};

void main() {
  late FakeAdapter server;
  late FakeAdapter cloud;
  late ImageUploader uploader;

  setUp(() {
    server = FakeAdapter((o, _) => json(signature));
    cloud = FakeAdapter((o, _) => json({'secure_url': 'https://res.cloudinary.com/test-cloud/image/upload/v1/classpluse/slides/l1/x.jpg'}));
    final api = ApiClient(token: () => 'jwt-token', dio: Dio(BaseOptions(baseUrl: 'http://server/api/v1'))..httpClientAdapter = server);
    uploader = ImageUploader(api, dio: Dio()..httpClientAdapter = cloud);
  });

  test('gets a signature, then posts the signed fields and file to Cloudinary', () async {
    final progress = <double>[];
    final url = await uploader.upload(UploadKind.slide, bytes: List.filled(200, 7), filename: 'photo.JPG', onProgress: progress.add);

    expect(url, endsWith('/classpluse/slides/l1/x.jpg'));
    expect(server.requests.single.options.path, '/uploads/signature');
    expect(server.requests.single.body, contains('"kind":"slide"'));

    final req = cloud.requests.single;
    expect(req.options.uri.toString(), signature['uploadUrl']);
    // Our API token must never be sent to Cloudinary.
    expect(req.options.headers.keys.map((k) => k.toLowerCase()), isNot(contains('authorization')));
    for (final field in ['api_key', 'signature', 'folder', 'timestamp', 'allowed_formats', 'transformation', 'file']) {
      expect(req.body, contains('name="$field"'));
    }
    expect(req.body, contains('classpluse/slides/l1'));
    expect(progress, isNotEmpty);
  });

  test('rejects other file types before contacting anything', () async {
    await expectLater(
      uploader.upload(UploadKind.slide, bytes: [1, 2, 3], filename: 'clip.gif'),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'INVALID_IMAGE')),
    );
    expect(server.requests, isEmpty);
    expect(cloud.requests, isEmpty);
  });

  test('rejects files over the size limit from the signature', () async {
    await expectLater(
      uploader.upload(UploadKind.avatar, bytes: List.filled(1001, 0), filename: 'big.png'),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('too large'))),
    );
    expect(cloud.requests, isEmpty);
  });

  test("passes on Cloudinary's error message", () async {
    cloud = FakeAdapter((o, _) => json({'error': {'message': 'Invalid Signature abc123'}}, 401));
    final api = ApiClient(token: () => 'jwt', dio: Dio(BaseOptions(baseUrl: 'http://server/api/v1'))..httpClientAdapter = server);
    uploader = ImageUploader(api, dio: Dio()..httpClientAdapter = cloud);
    await expectLater(
      uploader.upload(UploadKind.slide, bytes: [1], filename: 'a.png'),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'UPLOAD_FAILED').having((e) => e.message, 'message', contains('Invalid Signature'))),
    );
  });

  test('passes on server errors such as uploads being disabled', () async {
    server = FakeAdapter((o, _) => json({'error': {'code': 'UPLOADS_DISABLED', 'message': 'Image uploads are not set up on this server'}}, 503));
    final api = ApiClient(token: () => 'jwt', dio: Dio(BaseOptions(baseUrl: 'http://server/api/v1'))..httpClientAdapter = server);
    uploader = ImageUploader(api, dio: Dio()..httpClientAdapter = cloud);
    await expectLater(
      uploader.upload(UploadKind.slide, bytes: [1], filename: 'a.png'),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'UPLOADS_DISABLED')),
    );
    expect(cloud.requests, isEmpty);
  });
}
