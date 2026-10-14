// lib/services/notification_service.dart
import 'dart:async';
import 'dart:isolate';
import 'dart:ui';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_notification_listener/flutter_notification_listener.dart';
import 'message_storage_service.dart';
import 'buffer_service.dart';

const String _notificationPortName = 'notification_port';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  // UI로 데이터 보내주는 파이프 (Stream)
  final StreamController<String> _msgController =
      StreamController<String>.broadcast();
  Stream<String> get messageStream => _msgController.stream;

  // 상세 알림 정보를 위한 Stream
  final StreamController<NotificationData> _detailedMsgController =
      StreamController<NotificationData>.broadcast();
  Stream<NotificationData> get detailedMessageStream =>
      _detailedMsgController.stream;

  final BufferService _bufferService = const BufferService();

  ReceivePort? _port;
  bool _isInitialized = false; // 중복 초기화 방지

  // 1. 서비스 시작 (권한 체크 + 리스너 등록)
  Future<void> init() async {
    // 이미 초기화되었으면 스킵
    if (_isInitialized) {
      debugPrint("⚠️ 알림 서비스 이미 초기화됨 - 중복 초기화 방지");
      return;
    }

    final bool hasPermission =
        await NotificationsListener.hasPermission ?? false;
    if (!hasPermission) {
      debugPrint("알림 권한 없음 -> 설정창 이동");
      await NotificationsListener.openPermissionSettings();
      return;
    }

    // 백그라운드 통신 포트 열기
    _port = ReceivePort();
    IsolateNameServer.removePortNameMapping(_notificationPortName);
    IsolateNameServer.registerPortWithName(
      _port!.sendPort,
      _notificationPortName,
    );

    // 포트로 데이터 들어오면 처리
    _port!.listen(_onDataReceived);

    // 리스너 시작!
    debugPrint("알림 리스너 시작...");
    try {
      await NotificationsListener.initialize(
        callbackHandle: notificationTapBackground,
      );
      await NotificationsListener.startService();
      _isInitialized = true;
      debugPrint("✅ 알림 서비스 초기화 완료");
    } catch (e) {
      debugPrint("❌ 알림 서비스 시작 실패: $e");
      _isInitialized = false;
    }
  }

  // 서비스 중지
  void stop() {
    debugPrint("🛑 알림 서비스 중지 시작");
    _port?.close();
    _port = null;
    _isInitialized = false;
    debugPrint("✅ 알림 서비스 중지 완료");
  }

  // 2. 알림 데이터 처리 (여기가 핵심!)
  void _onDataReceived(dynamic event) async {
    if (event is! NotificationEvent) return;
    // event는 알림 정보 덩어리
    // 예: {title: "김미영 팀장", text: "대출 상담...", packageName: "com.samsung.android.messaging"}

    String packageName = event.packageName ?? "";
    String title = event.title ?? "알 수 없음";
    String content = event.text ?? "내용 없음"; // 이게 짧은 내용
    // String bigText = event['bigText'] ?? ""; // 이게 긴 내용 (지원하는 앱만 뜸)

    // ★ 필터링: 우리가 원하는 앱(문자, 카톡 등)만 감시할 수 있음
    // 지금은 테스트니까 다 보여줄게!
    debugPrint("🔔 알림 감지됨: [$packageName] $title : $content");

    // 화면(UI)으로 텍스트 쏘기
    _msgController.add("[$title] $content");

    // 배터리 절약을 위해 즉시 업로드 대신 로컬 버퍼에 적재
    final payload = jsonEncode({
      'title': title,
      'content': content,
      'packageName': packageName,
      'timestamp': DateTime.now().toIso8601String(),
    });
    await _bufferService.appendSms(payload);

    // ★ 메시지 저장 서비스에 저장 (비동기로 처리)
    final messageStorage = MessageStorageService();
    messageStorage
        .addMessage(title: title, content: content, packageName: packageName)
        .catchError((e) {
          debugPrint("❌ 메시지 저장 실패: $e");
        });

    // 상세 정보도 전달
    _detailedMsgController.add(
      NotificationData(
        title: title,
        content: content,
        packageName: packageName,
        timestamp: DateTime.now(),
      ),
    );
  }
}

/// 알림 데이터 모델
class NotificationData {
  final String title;
  final String content;
  final String packageName;
  final DateTime timestamp;

  NotificationData({
    required this.title,
    required this.content,
    required this.packageName,
    required this.timestamp,
  });
}

// (필수) 백그라운드에서 실행될 함수 (패키지 규칙임)
@pragma('vm:entry-point')
void notificationTapBackground(NotificationEvent evt) {
  // 백그라운드에서 알림 오면 이 함수가 실행됨
  final SendPort? send = IsolateNameServer.lookupPortByName(
    _notificationPortName,
  );
  if (send != null) {
    // 메인 앱으로 데이터 토스!
    send.send(evt);
  }
}
