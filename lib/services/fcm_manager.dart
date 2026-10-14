import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class FCMManager {
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  static Future<NotificationSettings>? _permissionInFlight;

  // 🔔 로컬 알림 플러그인 (앱 켜져 있을 때 알림 띄우기용)
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  // 🔴 [수정 필수] 본인의 서버 주소
  // - 에뮬레이터: http://10.0.2.2:8000/update-token
  // - 실제 기기: http://192.168.x.x:8000/update-token (WiFi 같은 네트워크)
  // - 배포 서버: http://10.0.2.2:8000/update-token
  final String serverUrl = "http://10.0.2.2:8000/update-token";

  /// 초기화 및 권한 요청
  Future<void> init(String userId) async {
    try {
      // 1) 로컬 알림 채널 설정 (안드로이드 필수) - 권한과 무관하게 준비
      await _setupLocalNotifications();

      // 2) 알림 권한 요청 (iOS/Android 13+)
      // 여러 화면에서 동시에 requestPermission()을 호출하면 예외가 날 수 있어 단일화합니다.
      try {
        _permissionInFlight ??= _firebaseMessaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
        final settings = await _permissionInFlight;
        debugPrint(
          '🔔 [FCM] 권한 상태: ${settings?.authorizationStatus ?? 'unknown'}',
        );
      } catch (e) {
        // 권한 요청 실패/중복 요청이어도 토큰 발급/서버 동기화는 계속 진행
        debugPrint('⚠️ [FCM] 권한 요청 실패(무시하고 계속): $e');
      } finally {
        _permissionInFlight = null;
      }

      // 3) 토큰 발급 및 서버 전송 (권한과 무관)
      await _syncTokenToServer(userId);

      // 4) 토큰 갱신 시 자동 재전송
      _firebaseMessaging.onTokenRefresh.listen((newToken) {
        debugPrint('FCM token refreshed');
        _syncTokenToServer(userId);
      });

      // 5. ⚡️ [핵심] 앱이 켜져 있을 때(Foreground) 알림 처리
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint(
          "📩 [FCM 수신-Foreground] ${message.notification?.title}: ${message.notification?.body}",
        );

        // 알림 내용이 있으면 -> 로컬 알림으로 직접 띄워줌!
        if (message.notification != null) {
          _showForegroundNotification(message);
        }
      });

      // 6. 백그라운드에서 알림 클릭 시 처리
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint("📲 [FCM 클릭] 알림에서 앱 열림");
        // 필요하면 특정 화면으로 이동
      });
    } catch (e) {
      debugPrint('❌ [FCM] 초기화 실패: $e');
    }
  }

  /// 🛠 안드로이드용 알림 채널 만들기 (필수 설정)
  Future<void> _setupLocalNotifications() async {
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'high_importance_channel', // id
      '비서 알림', // name (사용자 설정에 보임)
      description: '중요한 일정 알림을 받습니다.',
      importance: Importance.max, // 중요도 최대 (상단 배너 뜸)
      playSound: true,
    );

    // 플러그인 초기화
    await _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);

    // 아이콘 설정 (@mipmap/ic_launcher는 기본 앱 아이콘)
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS 설정 (기본값)
    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings();

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(initSettings);
  }

  /// 🔔 실제로 화면에 배너를 띄우는 함수
  Future<void> _showForegroundNotification(RemoteMessage message) async {
    RemoteNotification? notification = message.notification;
    AndroidNotification? android = message.notification?.android;

    if (notification != null) {
      await _localNotifications.show(
        notification.hashCode,
        notification.title,
        notification.body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'high_importance_channel', // 위에서 만든 채널 ID랑 같아야 함
            '비서 알림',
            channelDescription: '중요한 일정 알림',
            icon: '@mipmap/ic_launcher',
            importance: Importance.max,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true, // iOS 앱 켜져있을 때 알림 허용
            presentSound: true,
          ),
        ),
      );
      debugPrint('🔔 [FCM] Foreground 알림 표시 완료!');
    }
  }

  /// 토큰을 얻어서 서버로 전송하는 함수
  Future<void> _syncTokenToServer(String userId) async {
    try {
      // FCM 토큰 가져오기
      String? token = await _firebaseMessaging.getToken();

      if (token != null) {
        debugPrint('FCM token retrieved');

        // 0) Firestore(users/[가입이메일])에 먼저 반영 (merge)
        await _syncTokenToFirestore(userId, token);

        // 서버의 /update-token API 호출
        final response = await http.post(
          Uri.parse(serverUrl),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({"user_id": userId, "token": token}),
        );

        if (response.statusCode == 200) {
          debugPrint("🚀 [FCM] 서버에 토큰 전송 완료!");
        } else {
          debugPrint(
            "❌ [FCM] 토큰 전송 실패: ${response.statusCode} ${response.body}",
          );
        }
      } else {
        debugPrint("❌ [FCM] 토큰이 null입니다.");
      }
    } catch (e) {
      debugPrint("❌ [FCM] 토큰 동기화 에러: $e");
    }
  }

  Future<void> _syncTokenToFirestore(String userId, String token) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(userId).set({
        'fcmToken': token,
      }, SetOptions(merge: true));
      debugPrint('FCM token stored');
    } catch (e) {
      debugPrint('⚠️ [FCM] Firestore fcmToken 저장 실패: $e');
    }
  }

  /// 현재 토큰 가져오기 (디버그용)
  Future<String?> getToken() async {
    return await _firebaseMessaging.getToken();
  }
}
