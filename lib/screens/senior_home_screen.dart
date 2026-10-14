// lib/screens/senior_home_screen.dart
import 'care_home_main_screen.dart' show ChatbotTab;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:vibration/vibration.dart';
import 'package:just_audio/just_audio.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geocoding/geocoding.dart';
import 'dart:math';
import 'dart:async';
import 'dart:ui';
import 'package:shared_preferences/shared_preferences.dart';

import 'select_role_screen.dart';
import '../theme_state.dart';
import 'settings_screen.dart';
import '../services/call_recording_service.dart';
import '../services/video_upload_service.dart';
import 'media_upload_screen.dart';
import '../services/notification_service.dart';

class SeniorHomeScreen extends StatefulWidget {
  const SeniorHomeScreen({super.key});

  @override
  State<SeniorHomeScreen> createState() => _SeniorHomeScreenState();
}

class _SeniorHomeScreenState extends State<SeniorHomeScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _medicationAlertSub;
  static const String _prefsSeniorCodeKey = 'caremode_senior_code';

  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  String? myCode;
  Timer? _timer;
  final Battery _battery = Battery();

  StreamSubscription<String>? _notificationSubscription;
  String lastMessage = "아직 수신된 알림이 없습니다.";
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _notificationServiceInitialized = false; // 중복 초기화 방지

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _initLocalNotifications();

    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.05,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    _loadOrCreateCode();
    _checkPermissionAndStartTracking();

    _timer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      _uploadCallLog();
      _uploadStatus();
    });

    Future.delayed(const Duration(seconds: 2), _subscribeMedicationAlert);

    // 알림 서비스는 한 번만 초기화
    _initNotificationService();
  }

  Future<void> _initNotificationService() async {
    if (_notificationServiceInitialized) {
      debugPrint("⚠️ 알림 서비스 이미 초기화됨 - 중복 초기화 방지");
      return;
    }

    try {
      debugPrint("🔔 [SeniorHome] 알림 서비스 초기화 시도...");
      await NotificationService().init();
      _notificationServiceInitialized = true;

      _notificationSubscription?.cancel();
      _notificationSubscription = NotificationService().messageStream.listen((
        message,
      ) {
        debugPrint("🔔 [SeniorHome] UI 수신: $message");
        if (!mounted) return; // mounted 체크를 먼저

        setState(() {
          lastMessage = message;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('새 알림: $message'),
            duration: const Duration(milliseconds: 1500),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.indigo,
          ),
        );
      });
    } catch (e) {
      debugPrint("❌ 알림 서비스 연결 실패: $e");
      _notificationServiceInitialized = false;
    }
  }

  @override
  void dispose() {
    debugPrint("🧹 [SeniorHome] dispose 시작 - 리소스 정리");

    // 1. 애니메이션 컨트롤러
    _controller.dispose();

    // 2. 타이머 정리
    _timer?.cancel();
    _timer = null;

    // 3. 알림 구독 정리
    _notificationSubscription?.cancel();
    _notificationSubscription = null;

    // 4. 옵저버 제거
    WidgetsBinding.instance.removeObserver(this);

    // 5. 서비스 중지
    try {
      callRecordingService.stop();
    } catch (e) {
      debugPrint("⚠️ 통화 녹음 서비스 중지 실패: $e");
    }

    try {
      videoUploadService.stop();
    } catch (e) {
      debugPrint("⚠️ 비디오 업로드 서비스 중지 실패: $e");
    }

    // 6. 오디오 플레이어 정리
    _audioPlayer.dispose();

    // 7. Firestore 구독 정리
    _medicationAlertSub?.cancel();
    _medicationAlertSub = null;

    debugPrint("✅ [SeniorHome] dispose 완료");
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _uploadStatus();
    }
  }

  Future<void> _initLocalNotifications() async {
    const AndroidInitializationSettings androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosInit = DarwinInitializationSettings();
    const InitializationSettings initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );
    await _localNotifications.initialize(initSettings);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(canPop: false, child: _buildScaffold(context));
  }

  Widget _buildScaffold(BuildContext context) {
    final now = DateTime.now();
    final dateStr = DateFormat('M월 d일 EEEE', 'ko_KR').format(now);
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        title: const Text(
          "부모님 모드",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontFamily: 'Pyeongtaek',
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(isDark ? Icons.dark_mode : Icons.light_mode),
            onPressed: () => toggleTheme(),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const SettingsScreen()),
            ),
          ),
          IconButton(
            icon: Icon(Icons.logout, color: scheme.onSurface.withOpacity(0.7)),
            onPressed: () {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const SelectRoleScreen()),
                (route) => false,
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildGreetingSection(dateStr, scheme),
              const SizedBox(height: 20),
              _buildCodeCard(scheme, isDark),
              const SizedBox(height: 20),
              _buildStatusCards(scheme),
              const SizedBox(height: 20),
              _buildSeniorChatbotButton(context, isDark),
              const SizedBox(height: 20),
              _buildNotificationCard(scheme),
              const SizedBox(height: 20),
              _buildQuickActions(scheme),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGreetingSection(String dateStr, ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          dateStr,
          style: TextStyle(
            fontSize: 14,
            color: scheme.onSurface.withOpacity(0.6),
            fontFamily: 'Pyeongtaek',
          ),
        ),
        const SizedBox(height: 6),
        Text(
          "김철수님,\n${_getGreetingMessage()}",
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            fontFamily: 'Pyeongtaek',
            color: scheme.onSurface,
            height: 1.3,
          ),
        ),
      ],
    );
  }

  Widget _buildCodeCard(ColorScheme scheme, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF1E3A5F), const Color(0xFF0D253F)]
              : [scheme.primary, scheme.primary.withOpacity(0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.link, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "보호자 연결 코드",
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    SizedBox(height: 2),
                    Text(
                      "이 코드를 자녀분께 알려주세요",
                      style: TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withOpacity(0.3)),
            ),
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: Text(
                myCode ?? "생성 중...",
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 8,
                  fontFamily: 'Pyeongtaek',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCards(ColorScheme scheme) {
    return Row(
      children: [
        Expanded(
          child: _buildMiniStatusCard(
            icon: Icons.battery_charging_full,
            label: "배터리",
            value: "확인 중",
            color: Colors.green,
            scheme: scheme,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildMiniStatusCard(
            icon: Icons.location_on,
            label: "위치 공유",
            value: "활성화됨",
            color: Colors.blue,
            scheme: scheme,
          ),
        ),
      ],
    );
  }

  Widget _buildMiniStatusCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required ColorScheme scheme,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outline.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: scheme.onSurface.withOpacity(0.6),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeniorChatbotButton(BuildContext context, bool isDark) {
    return Center(
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(240, 70),
          backgroundColor: isDark
              ? const Color(0xFF667EEA)
              : const Color(0xFF764BA2),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          elevation: 8,
          shadowColor: Colors.black.withOpacity(0.2),
        ),
        icon: const Icon(Icons.chat_bubble_rounded, size: 36),
        label: const Text(
          'AI 챗봇',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            fontFamily: 'Pyeongtaek',
          ),
        ),
        onPressed: () {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (context) => DraggableScrollableSheet(
              initialChildSize: 0.92,
              minChildSize: 0.7,
              maxChildSize: 0.98,
              expand: false,
              builder: (context, scrollController) {
                return Container(
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF0F0F0F) : Colors.white,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(32),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 24,
                        offset: const Offset(0, -8),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 12, bottom: 8),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Expanded(child: ChatbotTab()),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildNotificationCard(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: lastMessage.contains("아직")
              ? scheme.outline.withOpacity(0.2)
              : Colors.redAccent.withOpacity(0.5),
          width: lastMessage.contains("아직") ? 1 : 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.notification_important,
                  color: Colors.redAccent,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  "실시간 알림 감지",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.circle, color: Colors.green, size: 8),
                    SizedBox(width: 4),
                    Text(
                      "활성",
                      style: TextStyle(
                        color: Colors.green,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withOpacity(0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              lastMessage,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: scheme.onSurface,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions(ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "빠른 기능",
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: scheme.onSurface,
          ),
        ),
        const SizedBox(height: 12),
        _buildServerUploadButton(scheme),
        const SizedBox(height: 12),
        _buildSOSButton(scheme),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildQuickActionButton(
                icon: Icons.phone,
                label: "긴급 연락",
                color: Colors.red,
                scheme: scheme,
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("긴급 연락 기능은 준비 중입니다.")),
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildQuickActionButton(
                icon: Icons.refresh,
                label: "새로고침",
                color: scheme.primary,
                scheme: scheme,
                onTap: () {
                  _uploadStatus();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("상태를 업데이트했습니다."),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildServerUploadButton(ColorScheme scheme) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          if (myCode == null) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('연결 코드가 없습니다.')));
            return;
          }
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MediaUploadScreen(userCode: myCode!),
            ),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? [const Color(0xFF1A237E), const Color(0xFF0D47A1)]
                  : [Colors.indigo, Colors.blue],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.blue.withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.cloud_upload_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '서버 업로드',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        fontFamily: 'Pyeongtaek',
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '동영상 • 사진 • 음성 파일 업로드',
                      style: TextStyle(fontSize: 13, color: Colors.white70),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios,
                color: Colors.white70,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSOSButton(ColorScheme scheme) {
    return _SOSButton(onSOSTriggered: () => _sendSOSAlert());
  }

  Widget _buildQuickActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required ColorScheme scheme,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: scheme.outline.withOpacity(0.2)),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _sendSOSAlert() async {
    final code = myCode;
    if (code == null) return;

    try {
      if (await Vibration.hasVibrator()) {
        Vibration.vibrate(pattern: [0, 200, 100, 200]);
      }

      Position? position;
      try {
        position = await Geolocator.getCurrentPosition();
      } catch (e) {
        debugPrint('위치 확인 실패: $e');
      }

      await FirebaseFirestore.instance.collection('users').doc(code).set({
        'sos': {
          'triggered': true,
          'timestamp': FieldValue.serverTimestamp(),
          'message': '긴급 도움 필요!',
          'location': position != null
              ? "${position.latitude}, ${position.longitude}"
              : "위치 미상",
        },
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('SOS 알림 전송됨!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('SOS 전송 실패'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _checkPermissionAndStartTracking() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      _uploadStatus();
    } catch (e) {
      debugPrint('위치 권한 오류: $e');
    }
  }

  Future<void> _loadOrCreateCode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefsSeniorCodeKey);
      if (saved != null && saved.length == 6) {
        if (!mounted) return;
        setState(() {
          myCode = saved;
        });
        await videoUploadService.start(
          saved,
          scanInterval: const Duration(seconds: 30),
        );
        return;
      }
    } catch (e) {
      debugPrint('$e');
    }
    await _generateAndSaveCode();
  }

  Future<void> _generateAndSaveCode() async {
    final users = FirebaseFirestore.instance.collection('users');
    String code;
    while (true) {
      code = (Random().nextInt(900000) + 100000).toString();
      final doc = await users.doc(code).get();
      if (!doc.exists) break;
    }

    if (!mounted) return;
    setState(() {
      myCode = code;
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsSeniorCodeKey, code);

    await videoUploadService.start(
      code,
      scanInterval: const Duration(seconds: 30),
    );

    await users.doc(code).set({
      'code': code,
      'createdAt': FieldValue.serverTimestamp(),
      'role': 'senior',
      'activity': '활동 중',
      'battery': 100,
    }, SetOptions(merge: true));
  }

  Future<void> _uploadStatus() async {
    final code = myCode;
    if (code == null) return;

    try {
      final level = await _battery.batteryLevel;
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition();
      } catch (e) {
        debugPrint('위치 에러: $e');
      }

      String? addressShort;
      if (position != null) {
        try {
          List<Placemark> placemarks = await placemarkFromCoordinates(
            position.latitude,
            position.longitude,
          );
          if (placemarks.isNotEmpty) {
            final p = placemarks.first;
            addressShort = "${p.locality ?? ''} ${p.subLocality ?? ''}".trim();
            if (addressShort.isEmpty) addressShort = p.thoroughfare;
          }
        } catch (_) {}
      }

      await FirebaseFirestore.instance.collection('users').doc(code).update({
        'battery': level,
        'lastActive': FieldValue.serverTimestamp(),
        if (position != null) ...{
          'latitude': position.latitude,
          'longitude': position.longitude,
          'locationAddressShort': addressShort,
        },
      });
    } catch (e) {
      debugPrint('상태 업로드 실패: $e');
    }
  }

  Future<void> _uploadCallLog() async {}

  String _getGreetingMessage() {
    final hour = DateTime.now().hour;
    if (hour < 11) return "오늘도 활기찬 아침!";
    if (hour < 14) return "점심 식사는 하셨나요?";
    if (hour < 18) return "나른한 오후, 힘내세요!";
    return "오늘 하루도 고생하셨어요";
  }

  void _subscribeMedicationAlert() {
    final code = myCode;
    if (code == null) return;
    _medicationAlertSub = FirebaseFirestore.instance
        .collection('users')
        .doc(code)
        .snapshots()
        .listen((snapshot) {
          if (!snapshot.exists) return;
          final data = snapshot.data();
          if (data == null) return;

          if (data.containsKey('medication_alert')) {
            final alert = data['medication_alert'] as Map<String, dynamic>;
            final triggered = alert['triggered'] == true;
            if (triggered) {
              Vibration.vibrate(pattern: [0, 500, 200, 500]);
              if (!mounted) return;
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('💊 약 드실 시간입니다!'),
                  content: const Text('보호자님이 약 복용 알림을 보냈어요.'),
                  actions: [
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                        FirebaseFirestore.instance
                            .collection('users')
                            .doc(code)
                            .update({'medication_alert.triggered': false});
                      },
                      child: const Text('확인'),
                    ),
                  ],
                ),
              );
            }
          }
        });
  }
}

class _SOSButton extends StatefulWidget {
  final VoidCallback onSOSTriggered;

  const _SOSButton({required this.onSOSTriggered});

  @override
  State<_SOSButton> createState() => _SOSButtonState();
}

class _SOSButtonState extends State<_SOSButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _progressAnimation;
  bool _isPressed = false;
  Timer? _pressTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _progressAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.linear));
  }

  @override
  void dispose() {
    _controller.dispose();
    _pressTimer?.cancel();
    super.dispose();
  }

  void _startPress() {
    if (!mounted) return;
    setState(() => _isPressed = true);
    _controller.duration = const Duration(seconds: 3);
    _controller.forward();
    _pressTimer = Timer(const Duration(seconds: 3), () {
      if (_isPressed && mounted) {
        widget.onSOSTriggered();
        _reset();
      }
    });
  }

  void _cancelPress() {
    if (_isPressed) {
      _reset();
    }
  }

  void _reset() {
    if (!mounted) return;
    setState(() => _isPressed = false);
    _pressTimer?.cancel();
    _controller.duration = const Duration(milliseconds: 200);
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _startPress(),
      onTapUp: (_) => _cancelPress(),
      onTapCancel: _cancelPress,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF5252), Color(0xFFD32F2F)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.red.withOpacity(0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
                border: _isPressed
                    ? Border.all(color: Colors.white, width: 2)
                    : null,
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.sos_rounded,
                        color: Colors.white,
                        size: 32,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _isPressed ? "계속 누르세요..." : "SOS 긴급 호출",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: _isPressed ? 20 : 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isPressed
                        ? "${(3 - (_progressAnimation.value * 3)).ceil()}초 후 전송"
                        : "3초간 길게 누르면 보호자에게 알림",
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 13,
                    ),
                  ),
                  if (_isPressed) ...[
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: LinearProgressIndicator(
                        value: _progressAnimation.value,
                        backgroundColor: Colors.white.withOpacity(0.3),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Colors.white,
                        ),
                        minHeight: 8,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
