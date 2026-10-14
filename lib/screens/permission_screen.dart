// lib/screens/permission_screen.dart
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'senior_home_screen.dart'; // 권한 다 받으면 여기로 이동
import '../services/onboarding_flag_service.dart';

class PermissionScreen extends StatefulWidget {
  const PermissionScreen({super.key});

  @override
  State<PermissionScreen> createState() => _PermissionScreenState();
}

class _PermissionScreenState extends State<PermissionScreen> {
  bool isLoading = false;

  // ★ 권한 요청 로직
  Future<void> _requestPermissions() async {
    setState(() => isLoading = true);

    // 필요한 권한들을 한방에 요청!
    await [
      Permission.location, // 위치
      Permission.phone, // 전화 상태
      Permission.microphone, // 마이크
      Permission.camera, // 카메라
      Permission.notification, // 알림
      // Permission.phoneLog는 구글 정책이 까다로워서 일단 뺌 (나중에 추가 가능)
    ].request();

    // 온보딩 완료 플래그 저장
    await OnboardingFlagService.setOnboardingCompleted();

    // 요청 끝나면 무조건 홈으로 이동 (쿨하게)
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const SeniorHomeScreen()),
      );
    }

    setState(() => isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. 헤더 멘트
              const Text(
                "편안하고 안전한\n하루를 위해",
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  height: 1.3,
                  fontFamily: 'Pyeongtaek',
                  color: Color(0xFF2D3142),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                "아래 권한들을 허용해주시면\n보호자가 어르신을 더 잘 챙겨드릴 수 있어요.",
                style: TextStyle(fontSize: 16, color: Colors.grey, height: 1.5),
              ),
              const SizedBox(height: 40),

              // 2. 권한 목록 (스크롤 가능)
              Expanded(
                child: ListView(
                  children: [
                    _buildPermissionItem(
                      icon: Icons.location_on_outlined,
                      color: Colors.orange,
                      title: "위치 정보",
                      desc: "외출하셨을 때 보호자가 위치를 확인할 수 있어요.",
                    ),
                    _buildPermissionItem(
                      icon: Icons.phone_in_talk_outlined,
                      color: Colors.green,
                      title: "전화 상태 확인",
                      desc: "통화 중이신지, 잘 계신지 확인할 수 있어요.",
                    ),
                    _buildPermissionItem(
                      icon: Icons.camera_alt_outlined,
                      color: Colors.blue,
                      title: "카메라",
                      desc: "오늘 하루 즐거웠던 순간을 사진으로 남겨요.",
                    ),
                    _buildPermissionItem(
                      icon: Icons.notifications_active_outlined,
                      color: Colors.redAccent,
                      title: "알림",
                      desc: "자녀분의 소식을 놓치지 않게 알려드려요.",
                    ),
                  ],
                ),
              ),

              // 3. 시작하기 버튼
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: isLoading ? null : _requestPermissions,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6C63FF),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          "확인하고 시작하기",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPermissionItem({
    required IconData icon,
    required Color color,
    required String title,
    required String desc,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2D3142),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  desc,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                    height: 1.4,
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
