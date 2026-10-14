// lib/screens/login_screen.dart
import 'package:flutter/material.dart';
import 'permission_screen.dart'; // ★★★ [중요] 이거 한 줄 추가하면 빨간 줄 사라짐!
import 'identity_onboarding_screen.dart';
import 'auth_login_screen.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 로고 영역 (그대로 유지)
              Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF5F66E1).withValues(alpha: 26),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.favorite,
                      size: 60,
                      color: Color(0xFF5F66E1),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    "하루매듭",
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Pyeongtaek',
                      color: Color(0xFF2D3142),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    "서로의 하루를 잇는 따뜻한 연결",
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                  ),
                ],
              ),

              const SizedBox(height: 60),

              // 1. 보호자 로그인 버튼
              ElevatedButton(
                onPressed: () async {
                  if (!context.mounted) return;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const AuthLoginScreen(),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF5F66E1),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  side: const BorderSide(color: Color(0xFF5F66E1), width: 1.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  "보호자(자녀)로 로그인",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),

              const SizedBox(height: 16),

              // 2. 부모님 시작 버튼 (★ 여기가 수정된 부분!)
              FilledButton(
                onPressed: () async {
                  final ok = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const IdentityOnboardingScreen(),
                    ),
                  );
                  if (ok == true && context.mounted) {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        // ★ 이제 빨간 줄 안 뜰 거야!
                        builder: (context) => const PermissionScreen(),
                      ),
                    );
                  }
                },
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF5F66E1),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  "부모님으로 시작하기",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
