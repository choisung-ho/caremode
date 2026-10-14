// lib/services/face_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

const String registerUrl = 'http://10.0.2.2:8000/register_face';
const String faceStreamUrl = 'ws://10.0.2.2:8000/ws/face_stream';

class FaceService {
  /// 얼굴 등록: personId와 여러 장의 사진을 멀티파트로 전송
  static Future<String?> registerFace({
    required String personId,
    required List<XFile> photos,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    if (photos.isEmpty) return '사진을 한 장 이상 첨부해주세요';

    final request = http.MultipartRequest('POST', Uri.parse(registerUrl));
    request.fields['person_id'] = personId;

    for (final photo in photos) {
      final bytes = await photo.readAsBytes();
      request.files.add(
        http.MultipartFile.fromBytes(
          'files',
          bytes,
          filename: photo.name,
          contentType: MediaType('image', 'jpeg'),
        ),
      );
    }

    try {
      debugPrint(
        '[FaceService] 업로드 시작: personId=$personId, files=${photos.length}',
      );
      final streamed = await request.send().timeout(timeout);
      final resp = await http.Response.fromStream(streamed);
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final json = jsonDecode(resp.body);
        final message = json['message']?.toString() ?? '등록 성공';
        debugPrint("[FaceService] 업로드 성공");
        return message;
      } else {
        final msg = '등록 실패: ${resp.statusCode} ${resp.body}';
        debugPrint('[FaceService] $msg');
        return msg;
      }
    } on TimeoutException catch (e) {
      final msg = '등록 실패: 요청 시간 초과 (${e.message ?? 'timeout'})';
      debugPrint('[FaceService] $msg');
      return msg;
    } catch (e) {
      final msg = '등록 실패: 네트워크 오류 ($e)';
      debugPrint('[FaceService] $msg');
      return msg;
    }
  }
}

/// 실시간 얼굴 인식 스트림 클라이언트 (웹소켓)
class FaceStreamClient {
  FaceStreamClient(this._controller);

  final CameraController _controller;
  WebSocketChannel? _channel;
  Timer? _timer;

  final StreamController<Map<String, dynamic>> _results =
      StreamController.broadcast();
  Stream<Map<String, dynamic>> get results => _results.stream;

  Future<void> start({
    Duration interval = const Duration(milliseconds: 150),
  }) async {
    if (_channel != null) return;
    _channel = WebSocketChannel.connect(Uri.parse(faceStreamUrl));

    _channel!.stream.listen((data) {
      try {
        final json = jsonDecode(data);
        _results.add(json as Map<String, dynamic>);
      } catch (_) {}
    }, onError: (e) => _results.add({'error': e.toString()}));

    _timer = Timer.periodic(interval, (_) async {
      if (!_controller.value.isInitialized ||
          _controller.value.isTakingPicture) {
        return;
      }
      try {
        final image = await _controller.takePicture();
        final bytes = await image.readAsBytes();
        _channel?.sink.add(bytes);
      } catch (e) {
        _results.add({'error': e.toString()});
      }
    });
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    await _channel?.sink.close();
    _channel = null;
  }
}
