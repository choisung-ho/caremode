// lib/screens/care_home_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'login_screen.dart';
import '../theme_state.dart';
import 'settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'select_role_screen.dart';
import '../services/notification_service.dart';
import '../services/message_storage_service.dart';

class CareHomeScreen extends StatefulWidget {
  const CareHomeScreen({super.key});

  @override
  State<CareHomeScreen> createState() => _CareHomeScreenState();
}

class _CareHomeScreenState extends State<CareHomeScreen> {
  // ★ 연결 상태 관리 (처음엔 false)

  bool isConnected = false;

  Map<String, dynamic>? seniorData; // 부모님 데이터 담을 변수

  String? _connectedCode;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _seniorDocSub;

  final TextEditingController _codeController = TextEditingController();

  bool isLoading = false;

  // SOS 알림 상태

  bool _showSOSAlert = false;

  Map<String, dynamic>? _sosData;

  static const String _prefsSeniorCodeKey = 'caremode_senior_code';

  // 메시지 관련

  StreamSubscription? _msgSub;
  String? _latestMsg;

  // 1. 파이어베이스 연결 함수

  Future<void> _connectToSenior({bool auto = false}) async {
    final inputCode = _codeController.text.trim();

    if (inputCode.length != 6) {
      if (!auto) {
        final snackBar = SnackBar(
          content: const Text(
            '6자리 코드를 정확히 입력해주세요.',
            style: TextStyle(fontSize: 14),
          ),
          duration: const Duration(milliseconds: 400),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          backgroundColor: Colors.black.withOpacity(0.85),
          behavior: SnackBarBehavior.floating,
        );
        ScaffoldMessenger.of(context).showSnackBar(snackBar);
      }
      return;
    }

    if (mounted) setState(() => isLoading = true);

    try {
      // 파이어베이스에서 코드 검색

      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(inputCode)
          .get();

      if (!mounted) return;

      if (snapshot.exists) {
        // 데이터가 있으면 가져와서 저장!

        setState(() {
          isConnected = true;

          seniorData = snapshot.data() as Map<String, dynamic>;

          _connectedCode = inputCode;
        });

        // 연결 코드 저장

        final prefs = await SharedPreferences.getInstance();

        await prefs.setString(_prefsSeniorCodeKey, inputCode);
      }
    } catch (e) {
      print("에러: $e");

      final snackBar = SnackBar(
        content: const Text('인터넷 연결을 확인해주세요.', style: TextStyle(fontSize: 14)),
        duration: const Duration(milliseconds: 400),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: Colors.black.withOpacity(0.85),
        behavior: SnackBarBehavior.floating,
      );
      ScaffoldMessenger.of(context).showSnackBar(snackBar);
    } finally {
      setState(() => isLoading = false);
    }
  }

  void _disconnect() async {
    _seniorDocSub?.cancel();
    _seniorDocSub = null;
    setState(() {
      isConnected = false;
      seniorData = null;
      _codeController.clear();
      _connectedCode = null;
    });
  }

  Future<void> _dismissSOS() async {
    setState(() {
      _showSOSAlert = false;

      _sosData = null;
    });
  }

  // 연결 유지 및 실시간 데이터 구독 시작

  void _connectAndSubscribe({bool auto = false}) async {
    final inputCode = _codeController.text.trim();

    if (inputCode.length != 6) return;

    try {
      // Firestore에서 사용자 데이터 가져오기

      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(inputCode)
          .get();

      if (!mounted) return;

      if (snapshot.exists) {
        // 데이터가 있으면 가져와서 저장!

        setState(() {
          isConnected = true;

          seniorData = snapshot.data() as Map<String, dynamic>;

          _connectedCode = inputCode;
        });

        // 연결 코드 저장

        final prefs = await SharedPreferences.getInstance();

        await prefs.setString(_prefsSeniorCodeKey, inputCode);

        // ★ 실시간 구독

        _seniorDocSub?.cancel();

        _seniorDocSub = FirebaseFirestore.instance
            .collection('users')
            .doc(inputCode)
            .snapshots()
            .listen((doc) {
              if (!doc.exists) return;

              if (!mounted) return;

              final data = doc.data();

              setState(() {
                seniorData = data;
              });

              // SOS 알림 체크

              _checkSOSAlert(data);
            });

        FocusScope.of(context).unfocus(); // 키보드 내리기

        if (!auto) {
          final snackBar = SnackBar(
            content: const Text(
              '실시간 데이터를 불러왔습니다. 🎉',
              style: TextStyle(fontSize: 14),
            ),
            duration: const Duration(milliseconds: 400),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            backgroundColor: Colors.black.withOpacity(0.85),
            behavior: SnackBarBehavior.floating,
          );
          ScaffoldMessenger.of(context).showSnackBar(snackBar);
        }
      } else {
        final snackBar = SnackBar(
          content: const Text(
            '잘못된 코드입니다. 다시 확인해주세요.',
            style: TextStyle(fontSize: 14),
          ),
          duration: const Duration(milliseconds: 400),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          backgroundColor: Colors.black.withOpacity(0.85),
          behavior: SnackBarBehavior.floating,
        );
        ScaffoldMessenger.of(context).showSnackBar(snackBar);
      }
    } catch (e) {
      print("에러: $e");

      final snackBar = SnackBar(
        content: const Text('인터넷 연결을 확인해주세요.', style: TextStyle(fontSize: 14)),
        duration: const Duration(milliseconds: 400),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: Colors.black.withOpacity(0.85),
        behavior: SnackBarBehavior.floating,
      );
      ScaffoldMessenger.of(context).showSnackBar(snackBar);
    } finally {
      setState(() => isLoading = false);
    }
  }

  // 연결 해제 (테스트용)

  Future<void> clearConnectionAndLogout(BuildContext context) async {
    _disconnect();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsSeniorCodeKey);
    // 로그아웃 시 모드 선택 화면(SelectRoleScreen)으로 이동
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const SelectRoleScreen()),
      (route) => false,
    );
  }

  @override
  void dispose() {
    _msgSub?.cancel();
    _seniorDocSub?.cancel();
    _codeController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // ★ 화면이 다 그려진 후 순차적으로 초기화 (ANR 방지)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeSequentially();
    });
  }

  /// ★ 순차적 초기화 - 메인 스레드 과부하 방지
  Future<void> _initializeSequentially() async {
    if (!mounted) return;

    // 1단계: 저장된 연결 복원 (가벼움)
    await _restoreConnection();
    if (!mounted) return;

    // 2단계: 잠시 대기 후 알림 리스너 시작
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    _initNotificationListener();
  }

  void _initNotificationListener() async {
    try {
      // 알림 권한 체크 및 리스너 시작
      await NotificationService().init();
      if (!mounted) return;

      _msgSub = MessageStorageService().messageStream.listen((messages) {
        if (messages.isNotEmpty && mounted) {
          setState(() {
            _latestMsg = messages.last.content;
          });
          // 실시간 알림 UI 표시 (예시)
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('새 문자: ${messages.last.content}')),
          );
        }
      });
    } catch (e) {
      debugPrint('❌ 알림 서비스 초기화 실패 (무시됨): $e');
    }
  }

  Future<void> _restoreConnection() async {
    final prefs = await SharedPreferences.getInstance();
    final savedCode = prefs.getString(_prefsSeniorCodeKey);
    if (savedCode != null && savedCode.length == 6) {
      // 자동 연결하지 않고 입력창에만 채워줌
      _codeController.text = savedCode;
      // 사용자가 직접 '연결하기' 버튼을 눌러야만 연결됨
    }
  }

  // SOS 알림 체크

  void _checkSOSAlert(Map<String, dynamic>? data) {
    if (data == null) return;

    final sos = data['sos'];

    if (sos is Map && sos['triggered'] == true) {
      // 이미 표시 중이 아니면 알림 표시

      if (!_showSOSAlert) {
        setState(() {
          _showSOSAlert = true;

          _sosData = Map<String, dynamic>.from(sos);
        });

        _showSOSDialog();
      }
    }
  }

  // SOS 다이얼로그 표시

  void _showSOSDialog() {
    showDialog(
      context: context,

      barrierDismissible: false,

      builder: (context) => AlertDialog(
        backgroundColor: Colors.red.shade50,

        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),

        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),

              decoration: BoxDecoration(
                color: Colors.red,

                borderRadius: BorderRadius.circular(12),
              ),

              child: const Icon(Icons.sos, color: Colors.white, size: 28),
            ),

            const SizedBox(width: 12),

            const Expanded(
              child: Text(
                '🚨 긴급 SOS 알림',

                style: TextStyle(
                  color: Colors.red,

                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),

        content: Column(
          mainAxisSize: MainAxisSize.min,

          crossAxisAlignment: CrossAxisAlignment.start,

          children: [
            const Text(
              '부모님께서 긴급 도움을 요청하셨습니다!',

              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),

            const SizedBox(height: 16),

            if (_sosData?['location'] != null) ...[
              Row(
                children: [
                  const Icon(Icons.location_on, color: Colors.red, size: 20),

                  const SizedBox(width: 8),

                  Expanded(
                    child: Text(
                      '위치: ${_sosData!['location']}',

                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),
            ],

            Row(
              children: [
                const Icon(Icons.access_time, color: Colors.grey, size: 20),

                const SizedBox(width: 8),

                Text(
                  '시간: ${DateTime.now().toString().substring(0, 19)}',

                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
              ],
            ),
          ],
        ),

        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);

              _dismissSOS();
            },

            child: const Text('확인했습니다'),
          ),

          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,

              foregroundColor: Colors.white,
            ),

            onPressed: () {
              Navigator.pop(context);

              _dismissSOS();

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('전화 연결 기능은 준비 중입니다.')),
              );
            },

            icon: const Icon(Icons.phone),

            label: const Text('전화 걸기'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,

      appBar: AppBar(
        backgroundColor: scheme.surface,

        foregroundColor: scheme.onSurface,

        elevation: 0,

        title: const Text(
          "보호자 모드",

          style: TextStyle(
            fontWeight: FontWeight.bold,

            fontFamily: 'Pyeongtaek',
          ),
        ),

        actions: [
          IconButton(
            tooltip: '테마 전환',

            icon: Icon(isDark ? Icons.dark_mode : Icons.light_mode),

            onPressed: () {
              toggleTheme();
            },
          ),

          IconButton(
            tooltip: '설정',

            icon: const Icon(Icons.settings_outlined),

            onPressed: () {
              Navigator.push(
                context,

                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
          ),

          IconButton(
            tooltip: '로그아웃',

            icon: Icon(
              Icons.logout,

              color: Theme.of(context).iconTheme.color?.withOpacity(0.8),
            ),

            onPressed: () async {
              await clearConnectionAndLogout(context);
            },
          ),
        ],
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,

          children: [
            const Text(
              "김철수님 (아들)",

              style: TextStyle(
                fontSize: 24,

                fontWeight: FontWeight.bold,

                fontFamily: 'Pyeongtaek',
              ),
            ),

            const SizedBox(height: 20),

            // ★ 연결 상태에 따라 화면 전환
            if (!isConnected)
              _buildConnectionCard() // 연결 안 됨 -> 입력창
            else
              _buildDashboard(), // 연결 됨 -> 대시보드 (데이터 화면)

            const SizedBox(height: 30),

            // 하단 섹션 (연결되었을 때만 보여줘도 되지만, 디자인상 유지)
            if (isConnected) ...[
              const Text(
                "실시간 활동 내역",

                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 10),

              // ★ [핵심] 서버에서 가져온 진짜 통화 기록 표시
              _buildActivityItem(
                Icons.phone_callback,

                "최근 통화 기록",

                "최신 업데이트", // 시간은 나중에 데이터에서 가져오면 됨

                seniorData?['lastCall'] ?? "아직 기록이 없어요.", // ★ 진짜 데이터!
              ),

              // (참고용 가짜 데이터 - 비교해보라고 남겨둠)
              _buildActivityItem(
                Icons.medication,

                "약 복용 알림",

                "1시간 전",

                "점심 약 드실 시간입니다.",
              ),
            ],
          ],
        ),
      ),
    );
  }

  // 1. 연결 입력창 카드

  Widget _buildConnectionCard() {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(24),

      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,

        borderRadius: BorderRadius.circular(20),

        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),

            blurRadius: 10,

            offset: const Offset(0, 5),
          ),
        ],
      ),

      child: Column(
        children: [
          Icon(Icons.link, size: 50, color: scheme.primary),

          const SizedBox(height: 10),

          const Text(
            "부모님과 연결해주세요",

            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 8),

          Text(
            "부모님 폰 화면 상단에 있는\n6자리 숫자를 입력해주세요.",

            textAlign: TextAlign.center,

            style: TextStyle(
              color: Theme.of(
                context,
              ).textTheme.bodyMedium?.color?.withOpacity(0.7),
            ),
          ),

          const SizedBox(height: 20),

          TextField(
            controller: _codeController,

            keyboardType: TextInputType.number,

            maxLength: 6,

            textAlign: TextAlign.center,

            decoration: InputDecoration(
              hintText: "123456",

              filled: true,

              fillColor: scheme.surface,

              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),

                borderSide: BorderSide.none,
              ),

              counterText: "",
            ),

            style: const TextStyle(
              fontSize: 24,

              letterSpacing: 5,

              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,

            child: ElevatedButton(
              onPressed: isLoading ? null : _connectToSenior,

              style: ElevatedButton.styleFrom(
                backgroundColor: scheme.primary,

                padding: const EdgeInsets.symmetric(vertical: 16),

                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),

              child: isLoading
                  ? const SizedBox(
                      height: 20,

                      width: 20,

                      child: CircularProgressIndicator(color: Colors.white),
                    )
                  : const Text("연결하기", style: TextStyle(fontSize: 18)),
            ),
          ),
        ],
      ),
    );
  }

  // 2. 대시보드 (데이터 보여주는 화면)

  Widget _buildDashboard() {
    final scheme = Theme.of(context).colorScheme;

    final isDark = themeNotifier.value == ThemeMode.dark;

    final locationShort = (seniorData?['locationAddressShort'] as String?)
        ?.trim();

    final lastMessage = seniorData?['lastMessage'];

    String lastMsgTime = '최신 업데이트';

    String lastMsgDesc = '아직 메시지가 없어요.';

    if (lastMessage is Map) {
      final appName = (lastMessage['app_name'] as String?)?.trim();

      final partner = (lastMessage['partner'] as String?)?.trim();

      final content = (lastMessage['content'] as String?)?.trim();

      final ts = (lastMessage['timestamp'] as String?)?.trim();

      if (ts != null && ts.isNotEmpty) lastMsgTime = ts;

      final header = <String>[
        if (appName != null && appName.isNotEmpty) appName,

        if (partner != null && partner.isNotEmpty) partner,
      ].join(' · ');

      final body = content ?? '';

      lastMsgDesc = header.isEmpty ? body : '$header: $body';

      if (lastMsgDesc.trim().isEmpty) lastMsgDesc = '아직 메시지가 없어요.';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,

      children: [
        // 메인 상태 카드
        Container(
          padding: const EdgeInsets.all(24),

          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? [const Color(0xFF1A3A4A), const Color(0xFF0D1F2D)]
                  : [const Color(0xFF43C6AC), const Color(0xFF191654)],

              begin: Alignment.topLeft,

              end: Alignment.bottomRight,
            ),

            borderRadius: BorderRadius.circular(24),

            boxShadow: [
              BoxShadow(
                color: (isDark ? Colors.black : const Color(0xFF43C6AC))
                    .withOpacity(0.3),

                blurRadius: 15,

                offset: const Offset(0, 10),
              ),
            ],
          ),

          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,

                children: [
                  const Text(
                    "어머니의 현재 상태",

                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),

                  Row(
                    children: [
                      GestureDetector(
                        onTap: () {
                          // 새로고침 - 연결 유지하면서 데이터만 다시 로드

                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('실시간 연결 중입니다.'),

                              duration: Duration(seconds: 1),
                            ),
                          );
                        },

                        child: const Icon(
                          Icons.sync,

                          color: Colors.white70,

                          size: 22,
                        ),
                      ),

                      const SizedBox(width: 12),

                      GestureDetector(
                        onTap: _disconnect,

                        child: const Icon(
                          Icons.link_off,

                          color: Colors.white70,

                          size: 22,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 20),

              Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white, size: 32),

                  const SizedBox(width: 12),

                  Expanded(
                    child: Text(
                      "현재 ${seniorData?['activity'] ?? '정상'} 상태이십니다.",

                      style: const TextStyle(
                        color: Colors.white,

                        fontSize: 20,

                        fontWeight: FontWeight.bold,

                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,

                children: [
                  Expanded(
                    child: _buildInfoItem(
                      Icons.battery_std,

                      "${seniorData?['battery'] ?? 0}%",

                      "배터리",
                    ),
                  ),

                  Expanded(
                    child: _buildInfoItem(
                      Icons.directions_walk,

                      "${seniorData?['stepCount'] ?? 0}",

                      "걸음",
                    ),
                  ),

                  Expanded(
                    flex: 2,

                    child: _buildInfoItem(
                      Icons.location_on,

                      (locationShort != null && locationShort.isNotEmpty)
                          ? locationShort
                          : (seniorData?['latitude'] != null
                                ? "위치 수신중"
                                : "확인 불가"),

                      "실시간 위치",
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 18),

              // 최근 메시지
              Align(
                alignment: Alignment.centerLeft,

                child: Text(
                  '최근 메시지',

                  style: TextStyle(
                    color: Colors.white.withOpacity(0.85),

                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              const SizedBox(height: 8),

              Container(
                width: double.infinity,

                padding: const EdgeInsets.all(14),

                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.10),

                  borderRadius: BorderRadius.circular(16),

                  border: Border.all(color: Colors.white.withOpacity(0.18)),
                ),

                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [
                    const Icon(
                      Icons.chat_bubble_outline,

                      color: Colors.white,

                      size: 20,
                    ),

                    const SizedBox(width: 10),

                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,

                        children: [
                          Text(
                            lastMsgTime,

                            style: TextStyle(
                              color: Colors.white.withOpacity(0.75),

                              fontSize: 12,
                            ),
                          ),

                          const SizedBox(height: 6),

                          Text(
                            lastMsgDesc,

                            maxLines: 2,

                            overflow: TextOverflow.ellipsis,

                            style: const TextStyle(
                              color: Colors.white,

                              fontSize: 14,

                              height: 1.25,

                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // 퀵 액션 그리드
        Text(
          "빠른 기능",

          style: TextStyle(
            fontSize: 18,

            fontWeight: FontWeight.bold,

            color: scheme.onSurface,
          ),
        ),

        const SizedBox(height: 12),

        GridView.count(
          shrinkWrap: true,

          physics: const NeverScrollableScrollPhysics(),

          crossAxisCount: 3,

          mainAxisSpacing: 12,

          crossAxisSpacing: 12,

          childAspectRatio: 1,

          children: [
            _buildQuickAction(
              icon: Icons.phone,

              label: "긴급 연락",

              color: Colors.red,

              scheme: scheme,

              onTap: () => _showEmergencyDialog(),
            ),

            _buildQuickAction(
              icon: Icons.note_alt,

              label: "케어 일지",

              color: Colors.orange,

              scheme: scheme,

              onTap: () => _showCareLogDialog(),
            ),

            _buildQuickAction(
              icon: Icons.notifications_active,

              label: "SOS 알림",

              color: Colors.purple,

              scheme: scheme,

              onTap: () {
                final snackBar = SnackBar(
                  content: const Text(
                    'SOS 알림 기능은 준비 중입니다.',
                    style: TextStyle(fontSize: 14),
                  ),
                  duration: const Duration(milliseconds: 400),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  backgroundColor: Colors.black.withOpacity(0.85),
                  behavior: SnackBarBehavior.floating,
                );
                ScaffoldMessenger.of(context).showSnackBar(snackBar);
              },
            ),

            _buildQuickAction(
              icon: Icons.map,

              label: "위치 보기",

              color: Colors.blue,

              scheme: scheme,

              onTap: () {
                final lat = seniorData?['latitude'];

                final lng = seniorData?['longitude'];

                if (lat != null && lng != null) {
                  final snackBar = SnackBar(
                    content: Text(
                      '위치: $lat, $lng',
                      style: const TextStyle(fontSize: 14),
                    ),
                    duration: const Duration(milliseconds: 400),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    backgroundColor: Colors.black.withOpacity(0.85),
                    behavior: SnackBarBehavior.floating,
                  );
                  ScaffoldMessenger.of(context).showSnackBar(snackBar);
                } else {
                  final snackBar = SnackBar(
                    content: const Text(
                      '위치 정보가 없습니다.',
                      style: TextStyle(fontSize: 14),
                    ),
                    duration: const Duration(milliseconds: 400),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    backgroundColor: Colors.black.withOpacity(0.85),
                    behavior: SnackBarBehavior.floating,
                  );
                  ScaffoldMessenger.of(context).showSnackBar(snackBar);
                }
              },
            ),

            _buildQuickAction(
              icon: Icons.history,

              label: "알림 내역",

              color: Colors.teal,

              scheme: scheme,

              onTap: () {
                final snackBar = SnackBar(
                  content: const Text(
                    '알림 내역 기능은 준비 중입니다.',
                    style: TextStyle(fontSize: 14),
                  ),
                  duration: const Duration(milliseconds: 400),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  backgroundColor: Colors.black.withOpacity(0.85),
                  behavior: SnackBarBehavior.floating,
                );
                ScaffoldMessenger.of(context).showSnackBar(snackBar);
              },
            ),

            _buildQuickAction(
              icon: Icons.schedule,

              label: "약 알림",

              color: Colors.green,

              scheme: scheme,

              onTap: () {
                if (_connectedCode == null) {
                  final snackBar = SnackBar(
                    content: const Text(
                      '부모님과 먼저 연결해주세요.',
                      style: TextStyle(fontSize: 14),
                    ),
                    duration: const Duration(milliseconds: 400),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    backgroundColor: Colors.black.withOpacity(0.85),
                    behavior: SnackBarBehavior.floating,
                  );
                  ScaffoldMessenger.of(context).showSnackBar(snackBar);
                  return;
                }
                // Firestore에 약 알림 트리거 기록
                FirebaseFirestore.instance
                    .collection('users')
                    .doc(_connectedCode)
                    .set({
                      'medication_alert': {
                        'triggered': true,
                        'timestamp': FieldValue.serverTimestamp(),
                      },
                      'updatedAt': FieldValue.serverTimestamp(),
                    }, SetOptions(merge: true));
                final snackBar = SnackBar(
                  content: const Text(
                    '약 복용 알림을 전송했습니다!',
                    style: TextStyle(fontSize: 14),
                  ),
                  duration: const Duration(milliseconds: 400),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  backgroundColor: Colors.black.withOpacity(0.85),
                  behavior: SnackBarBehavior.floating,
                );
                ScaffoldMessenger.of(context).showSnackBar(snackBar);
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildQuickAction({
    required IconData icon,

    required String label,

    required Color color,

    required ColorScheme scheme,

    required VoidCallback onTap,
  }) {
    return Material(
      color: Theme.of(context).cardColor,

      borderRadius: BorderRadius.circular(16),

      child: InkWell(
        onTap: onTap,

        borderRadius: BorderRadius.circular(16),

        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),

            border: Border.all(color: scheme.outline.withOpacity(0.15)),
          ),

          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,

            children: [
              Container(
                padding: const EdgeInsets.all(10),

                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),

                  borderRadius: BorderRadius.circular(12),
                ),

                child: Icon(icon, color: color, size: 24),
              ),

              const SizedBox(height: 8),

              Text(
                label,

                style: TextStyle(
                  fontSize: 12,

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

  void _showEmergencyDialog() {
    showDialog(
      context: context,

      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.phone, color: Colors.red),

            SizedBox(width: 8),

            Text('긴급 연락'),
          ],
        ),

        content: const Text('부모님께 긴급 전화를 거시겠습니까?'),

        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),

            child: const Text('취소'),
          ),

          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),

            onPressed: () {
              Navigator.pop(context);

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('전화 연결 기능은 준비 중입니다.')),
              );
            },

            child: const Text('전화 걸기'),
          ),
        ],
      ),
    );
  }

  void _showCareLogDialog() {
    final controller = TextEditingController();

    showDialog(
      context: context,

      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.note_alt, color: Colors.orange),

            SizedBox(width: 8),

            Text('케어 일지'),
          ],
        ),

        content: TextField(
          controller: controller,

          maxLines: 4,

          decoration: const InputDecoration(
            hintText: '오늘의 케어 내용을 기록해주세요...',

            border: OutlineInputBorder(),
          ),
        ),

        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),

            child: const Text('취소'),
          ),

          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);

              if (controller.text.trim().isNotEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('케어 일지가 저장되었습니다.')),
                );
              }
            },

            child: const Text('저장'),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, color: Colors.white, size: 28),

        const SizedBox(height: 8),

        Text(
          value,

          style: const TextStyle(
            color: Colors.white,

            fontSize: 14,

            fontWeight: FontWeight.bold,
          ),

          textAlign: TextAlign.center,

          maxLines: 2,

          overflow: TextOverflow.ellipsis,
        ),

        Text(
          label,

          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildActivityItem(
    IconData icon,

    String title,

    String time,

    String desc,
  ) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),

      padding: const EdgeInsets.all(16),

      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,

        borderRadius: BorderRadius.circular(16),

        border: Border.all(color: scheme.outline.withOpacity(0.15)),
      ),

      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),

            decoration: BoxDecoration(
              color: scheme.primary.withOpacity(0.1),

              borderRadius: BorderRadius.circular(12),
            ),

            child: Icon(icon, color: scheme.primary),
          ),

          const SizedBox(width: 16),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,

                  children: [
                    Text(
                      title,

                      style: const TextStyle(
                        fontWeight: FontWeight.bold,

                        fontSize: 16,
                      ),
                    ),

                    Text(
                      time,

                      style: TextStyle(
                        color: scheme.onSurface.withOpacity(0.5),

                        fontSize: 12,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 4),

                Text(
                  desc,

                  style: TextStyle(
                    color: scheme.onSurface.withOpacity(0.7),

                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
