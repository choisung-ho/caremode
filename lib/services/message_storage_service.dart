// lib/services/message_storage_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
// import 'notification_service.dart'; // 미사용 import 제거
import 'package:cloud_firestore/cloud_firestore.dart';

/// 메시지 모델
class MessageItem {
  final String id;
  final String title; // 발신자
  final String content; // 메시지 내용
  final String packageName; // 앱 패키지명
  final DateTime timestamp;
  bool isUploaded;

  MessageItem({
    required this.id,
    required this.title,
    required this.content,
    required this.packageName,
    required this.timestamp,
    this.isUploaded = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'content': content,
    'packageName': packageName,
    'timestamp': timestamp.toIso8601String(),
    'isUploaded': isUploaded,
  };

  factory MessageItem.fromJson(Map<String, dynamic> json) => MessageItem(
    id: json['id'] ?? '',
    title: json['title'] ?? '',
    content: json['content'] ?? '',
    packageName: json['packageName'] ?? '',
    timestamp: DateTime.parse(json['timestamp']),
    isUploaded: json['isUploaded'] ?? false,
  );

  String get formattedDate {
    return '${timestamp.month}/${timestamp.day} ${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')}';
  }

  String get appName {
    // 패키지명을 기반으로 앱 이름 반환
    if (packageName.contains('messaging') || packageName.contains('mms')) {
      return '문자';
    } else if (packageName.contains('kakao')) {
      return '카카오톡';
    } else if (packageName.contains('telegram')) {
      return '텔레그램';
    } else if (packageName.contains('whatsapp')) {
      return 'WhatsApp';
    } else if (packageName.contains('instagram')) {
      return '인스타그램';
    } else if (packageName.contains('facebook')) {
      return 'Facebook';
    } else if (packageName.contains('line')) {
      return 'LINE';
    }
    return '기타';
  }
}

/// 메시지 저장 및 관리 서비스
class MessageStorageService {
  static final MessageStorageService _instance =
      MessageStorageService._internal();
  factory MessageStorageService() => _instance;
  MessageStorageService._internal();

  final List<MessageItem> _messages = [];
  List<MessageItem> get messages => List.unmodifiable(_messages);

  StreamSubscription<String>? _notificationSub;

  // 메시지 변경 알림용 StreamController
  final StreamController<List<MessageItem>> _messageStreamController =
      StreamController<List<MessageItem>>.broadcast();
  Stream<List<MessageItem>> get messageStream =>
      _messageStreamController.stream;

  bool _initialized = false;

  /// 서비스 초기화 (메시지 로드만 수행, NotificationService는 senior_home_screen에서 관리)
  Future<void> init() async {
    if (_initialized) {
      debugPrint('📱 MessageStorageService 이미 초기화됨');
      return;
    }

    // 저장된 메시지 로드
    await _loadMessages();
    _initialized = true;

    debugPrint('📱 MessageStorageService 초기화 완료 (메시지 ${_messages.length}개)');
  }

  /// Firestore에 메시지 업로드
  Future<void> uploadMessageToFirestore(MessageItem message) async {
    try {
      await FirebaseFirestore.instance.collection('client_messages').add({
        'id': message.id,
        'title': message.title,
        'content': message.content,
        'packageName': message.packageName,
        'timestamp': message.timestamp.toIso8601String(),
        'isUploaded': message.isUploaded,
      });
      debugPrint('✅ Firestore에 메시지 업로드 완료: ${message.id}');
    } catch (e) {
      debugPrint('❌ Firestore 업로드 실패: $e');
    }
  }

  /// 상세 알림 정보로 메시지 추가 (확장된 NotificationService용)
  Future<void> addMessage({
    required String title,
    required String content,
    required String packageName,
  }) async {
    // 초기화 안 됐으면 먼저 로드
    if (!_initialized) {
      await _loadMessages();
      _initialized = true;
    }

    // 모든 메시지 저장 (필터링 없이)
    final message = MessageItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      content: content,
      packageName: packageName,
      timestamp: DateTime.now(),
    );

    _messages.insert(0, message);

    // Firestore에 업로드 추가
    await uploadMessageToFirestore(message);

    // 최대 1000개까지만 보관
    if (_messages.length > 1000) {
      _messages.removeRange(1000, _messages.length);
    }

    await _saveMessages();
    _messageStreamController.add(_messages);

    // debugPrint('💬 메시지 저장됨: [$title] $content (${message.appName})'); // 미사용 코드 제거
  }

  /// 메시지를 업로드됨으로 표시
  void markAsUploaded(String messageId) {
    final index = _messages.indexWhere((m) => m.id == messageId);
    if (index != -1) {
      _messages[index].isUploaded = true;
      _saveMessages();
      _messageStreamController.add(_messages);
    }
  }

  /// 여러 메시지를 업로드됨으로 표시
  void markMultipleAsUploaded(List<String> messageIds) {
    for (final id in messageIds) {
      final index = _messages.indexWhere((m) => m.id == id);
      if (index != -1) {
        _messages[index].isUploaded = true;
      }
    }
    _saveMessages();
    _messageStreamController.add(_messages);
  }

  /// 업로드되지 않은 메시지 가져오기
  List<MessageItem> getUnuploadedMessages() {
    return _messages.where((m) => !m.isUploaded).toList();
  }

  /// 메시지를 JSON 파일로 내보내기
  Future<File> exportToJsonFile() async {
    final dir = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final file = File('${dir.path}/messages_$timestamp.json');

    final unuploaded = getUnuploadedMessages();
    final jsonData = jsonEncode(unuploaded.map((m) => m.toJson()).toList());

    await file.writeAsString(jsonData);
    return file;
  }

  /// 특정 메시지들을 JSON 파일로 내보내기
  Future<File> exportMessagesToFile(List<MessageItem> messagesToExport) async {
    final dir = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final file = File('${dir.path}/messages_$timestamp.json');

    final jsonData = jsonEncode(
      messagesToExport.map((m) => m.toJson()).toList(),
    );

    await file.writeAsString(jsonData);
    return file;
  }

  /// 메시지 저장
  Future<void> _saveMessages() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = _messages.map((m) => jsonEncode(m.toJson())).toList();
      await prefs.setStringList('saved_messages', jsonList);
    } catch (e) {
      debugPrint('❌ 메시지 저장 실패: $e');
    }
  }

  /// 메시지 로드
  Future<void> _loadMessages() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = prefs.getStringList('saved_messages') ?? [];

      _messages.clear();
      for (final jsonStr in jsonList) {
        final map = jsonDecode(jsonStr) as Map<String, dynamic>;
        _messages.add(MessageItem.fromJson(map));
      }

      debugPrint('📋 저장된 메시지 ${_messages.length}개 로드됨');
    } catch (e) {
      debugPrint('❌ 메시지 로드 실패: $e');
    }
  }

  /// 모든 메시지 삭제
  Future<void> clearAllMessages() async {
    _messages.clear();
    await _saveMessages();
    _messageStreamController.add(_messages);
  }

  /// 서비스 종료
  void dispose() {
    _notificationSub?.cancel();
    _messageStreamController.close();
  }
}
