// lib/screens/select_role_screen.dart
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/wake_word_manager.dart';
import 'identity_onboarding_screen.dart';
import 'storytelling_demo_screen.dart';
import 'auth_login_screen.dart';
import 'voice_chat_screen.dart';

class SelectRoleScreen extends StatefulWidget {
  const SelectRoleScreen({super.key});

  @override
  State<SelectRoleScreen> createState() => _SelectRoleScreenState();
}

class _SelectRoleScreenState extends State<SelectRoleScreen> {
  WakeWordManager? _wakeWordManager;
  bool _isWakeWordActive = false;

  @override
  void initState() {
    super.initState();
    _setupWakeWord();
  }

  Future<void> _setupWakeWord() async {
    debugPrint("🎯 [SELECT_ROLE] 웨이크워드 설정 시작...");

    // 마이크 권한 요청
    var status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      debugPrint("❌ [SELECT_ROLE] 마이크 권한이 거부되었습니다.");
      return;
    }
    debugPrint("✅ [SELECT_ROLE] 마이크 권한 허용됨");

    // 웨이크 워드 매니저 설정
    _wakeWordManager = WakeWordManager(
      onWakeWordDetected: (keywordIndex) async {
        debugPrint("✨✨✨ [감지 성공] 웨이크 워드 감지! AI 비서 화면으로 이동...");

        // 중요: 웨이크 워드 엔진 중지 (마이크 충돌 방지)
        await _wakeWordManager?.stopListening();
        setState(() => _isWakeWordActive = false);

        // AI 비서 화면으로 이동
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const VoiceChatScreen()),
          ).then((_) {
            // 화면에서 돌아오면 다시 웨이크 워드 대기
            debugPrint("🔄 AI 비서 종료, 다시 웨이크 워드 대기 모드...");
            _wakeWordManager?.startListening();
            setState(() => _isWakeWordActive = true);
          });
        }
      },
    );

    // 엔진 초기화 및 듣기 시작
    debugPrint("🔧 [SELECT_ROLE] 웨이크워드 엔진 초기화 중...");

    try {
      await _wakeWordManager?.init();
      debugPrint("🎤 [SELECT_ROLE] 웨이크워드 듣기 시작 중...");
      await _wakeWordManager?.startListening();
      setState(() => _isWakeWordActive = true);
      debugPrint("✅ [SELECT_ROLE] 웨이크워드 대기 모드 활성화 완료!");
    } catch (e) {
      debugPrint("❌ [SELECT_ROLE] 웨이크워드 초기화 실패: $e");
      setState(() => _isWakeWordActive = false);

      // 사용자에게 알림
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('웨이크워드 초기화 실패: 언어 불일치 또는 파일 문제'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 5),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _wakeWordManager?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 웨이크 워드 상태 표시
                if (_isWakeWordActive)
                  Container(
                    margin: const EdgeInsets.only(bottom: 20),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF5C6BC0).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFF5C6BC0),
                        width: 1.5,
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.mic, color: Color(0xFF5C6BC0), size: 16),
                        SizedBox(width: 8),
                        Text(
                          '"윤여민" 이라고 불러보세요',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF5C6BC0),
                          ),
                        ),
                      ],
                    ),
                  ),
                // 하트 아이콘 영역
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8EAF6), // 연한 보라색 배경
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.favorite,
                    color: Color(0xFF5C6BC0), // 보라색 하트
                    size: 40,
                  ),
                ),
                const SizedBox(height: 24),
                // 하루매듭 타이틀
                const Text(
                  "하루매듭",
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF37474F),
                  ),
                ),
                const SizedBox(height: 12),
                // 서브 타이틀
                const Text(
                  "서로의 하루를 잇는 따듯한 연결",
                  style: TextStyle(fontSize: 16, color: Color(0xFF78909C)),
                ),
                const SizedBox(height: 60),
                // 보호자 로그인 버튼 (아웃라인)
                _buildOutlineButton(
                  context,
                  "보호자(자녀)로 로그인",
                  const Color(0xFF5C6BC0),
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AuthLoginScreen()),
                  ),
                ),
                const SizedBox(height: 16),
                // 부모님 시작 버튼 (채워진 버튼)
                _buildFilledButton(
                  context,
                  "부모님으로 시작하기",
                  const Color(0xFF5C6BC0),
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const IdentityOnboardingScreen(),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                // 데모 스토리텔링 버튼
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF5C6BC0),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const StorytellingDemoScreen(),
                        ),
                      );
                    },
                    child: const Text(
                      '스토리텔링 테스트모드',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // 🎤 AI 음성 비서 버튼 (신규)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF667EEA),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      elevation: 4,
                      shadowColor: const Color(0xFF667EEA).withOpacity(0.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const VoiceChatScreen(),
                        ),
                      );
                    },
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.mic, size: 24),
                        SizedBox(width: 8),
                        Text(
                          'AI 음성 비서 (테스트)',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOutlineButton(
    BuildContext context,
    String text,
    Color color,
    VoidCallback onTap,
  ) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: color),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 16,
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildFilledButton(
    BuildContext context,
    String text,
    Color color,
    VoidCallback onTap,
  ) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(
          text,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
