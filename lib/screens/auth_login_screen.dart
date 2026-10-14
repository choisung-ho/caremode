import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/auth_service.dart';
import '../services/fcm_manager.dart';
import 'care_home_main_screen.dart';
import 'permission_screen.dart';
import 'auth_signup_screen.dart';

class AuthLoginScreen extends StatefulWidget {
  const AuthLoginScreen({super.key});

  @override
  State<AuthLoginScreen> createState() => _AuthLoginScreenState();
}

class _AuthLoginScreenState extends State<AuthLoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// ✅ FCM 토큰 서버에 업데이트
  Future<void> _updateFCMToken(String email) async {
    try {
      // ✅ 백엔드가 요구하는 구조: 로그인 시점에 토큰을 자동 생성/등록
      // Firestore 문서 키가 가입 이메일이라면, userId 자리에 email을 보내는 게 가장 단순합니다.
      await FCMManager().init(email);
    } catch (e) {
      debugPrint('❌ [로그인] FCM 토큰 업데이트 실패: $e');
    }
  }

  Future<void> _onLoginPressed() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('이메일과 비밀번호를 입력해주세요.')));
      return;
    }

    setState(() => _isLoading = true);

    final service = AuthService();
    final role = await service.login(email: email, password: password);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (role == null) {
      final msg = service.lastError ?? '로그인 실패! 이메일과 비밀번호를 확인하세요.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      return;
    }

    // ✅ 로그인 성공 후 FCM 토큰 서버에 업데이트
    await _updateFCMToken(email);

    if (role == 1) {
      // 보호자 모드 진입 시 연결코드 초기화(자동연결 방지)
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('caremode_senior_code');

      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const CareHomeMainScreen()),
        (_) => false,
      );
      return;
    }

    if (role == 2) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const PermissionScreen()),
        (_) => false,
      );
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('알 수 없는 role 값입니다: $role')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF37474F),
        elevation: 0,
        title: const Text('로그인'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              const Text(
                '하루매듭',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF37474F),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '서버: ${AuthService.baseUrl}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Color(0xFF78909C)),
              ),
              const SizedBox(height: 36),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: '이메일',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                obscureText: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _isLoading ? null : _onLoginPressed(),
                decoration: InputDecoration(
                  labelText: '비밀번호',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _onLoginPressed,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF5C6BC0),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          '로그인',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _isLoading
                      ? null
                      : () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const AuthSignupScreen(),
                            ),
                          );
                        },
                  child: const Text('회원가입'),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                "안드로이드 에뮬레이터는 10.0.2.2 사용\n실기기는 PC IP로 AUTH_API_BASE_URL을 지정하세요.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Color(0xFF78909C)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
