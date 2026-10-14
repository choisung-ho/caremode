// lib/main.dart
import 'dart:isolate';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'firebase_options.dart';
import 'package:flutter_notification_listener/flutter_notification_listener.dart'
    hide callbackDispatcher;

import 'theme_state.dart';
import 'services/call_recording_service.dart';
import 'screens/select_role_screen.dart';

const String notificationListenerPortName = 'caremode_notification_port';

@pragma('vm:entry-point')
void onNotificationEvent(NotificationEvent event) {
  debugPrint("알림 수신: $event");

  // ★ 통화 녹음 완료 알림 감지 → 업로드 트리거
  final pkg = event.packageName ?? '';
  final title = event.title ?? '';
  if (pkg == 'com.samsung.android.incallui' && title.contains('통화 녹음 완료')) {
    debugPrint('🎙️ [main.dart] 통화 녹음 완료 알림 감지! 3초 후 업로드 시작...');
    Future.delayed(const Duration(seconds: 3), () {
      CallRecordingService().scanAndUploadNewRecordings();
    });
  }
  final SendPort? port = IsolateNameServer.lookupPortByName(
    notificationListenerPortName,
  );
  port?.send(event);
}

// 라이트/다크 테마 정의
final lightTheme = ThemeData(
  useMaterial3: true,
  colorSchemeSeed: Colors.teal,
  fontFamily: 'Pyeongtaek',
  scaffoldBackgroundColor: const Color(0xFFF5F7FA),
  brightness: Brightness.light,
  pageTransitionsTheme: const PageTransitionsTheme(
    builders: {
      TargetPlatform.android: CupertinoPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    },
  ),
);

final darkTheme = ThemeData(
  useMaterial3: true,
  colorSchemeSeed: Colors.teal,
  fontFamily: 'Pyeongtaek',
  brightness: Brightness.dark,
  scaffoldBackgroundColor: const Color(0xFF121212),
  pageTransitionsTheme: const PageTransitionsTheme(
    builders: {
      TargetPlatform.android: CupertinoPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    },
  ),
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 전역 에러 핸들러 설정 (앱 크래시 방지)
  FlutterError.onError = (FlutterErrorDetails details) {
    debugPrint('🔴 Flutter 에러 발생: ${details.exception}');
    debugPrint('스택 트레이스: ${details.stack}');
    // 실제 프로덕션에서는 Firebase Crashlytics 등으로 전송
  };

  // Dart 에러 핸들러
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('🔴 Dart 에러 발생: $error');
    debugPrint('스택 트레이스: $stack');
    return true; // 에러를 처리했음을 알림
  };

  await initializeDateFormatting('ko_KR', null);

  if (kIsWeb) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } else {
    await Firebase.initializeApp();
  }

  // WorkManager 초기화 및 주기 작업 등록 (안드로이드 전용)
  // 백그라운드 워커 안정화 전까지 주기 작업 등록을 잠시 비활성화
  if (!kIsWeb) {
    // await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
    // await Workmanager().registerPeriodicTask(
    //   periodicTaskName,
    //   periodicTaskName,
    //   frequency: const Duration(hours: 2),
    //   constraints: Constraints(networkType: NetworkType.connected),
    //   existingWorkPolicy: ExistingWorkPolicy.keep,
    // );
  }

  await loadThemeModeFromPrefs();

  // ★ 기존 온보딩 체크 로직 제거하고 바로 실행
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, currentMode, child) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: '하루매듭',
          theme: lightTheme,
          darkTheme: darkTheme,
          themeMode: currentMode,
          themeAnimationDuration: const Duration(milliseconds: 300),
          themeAnimationCurve: Curves.easeInOut,
          // ★ 앱을 켜면 무조건 '모드 선택' 화면부터 시작
          home: const SelectRoleScreen(),
        );
      },
    );
  }
}
