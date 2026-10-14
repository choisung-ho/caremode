import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart'; // ✅ FCM 추가

import '../services/auth_service.dart';

class AuthSignupScreen extends StatefulWidget {
  const AuthSignupScreen({super.key});

  @override
  State<AuthSignupScreen> createState() => _AuthSignupScreenState();
}

class _AuthSignupScreenState extends State<AuthSignupScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _birthController = TextEditingController();
  final _phoneController = TextEditingController();
  final _homeLatController = TextEditingController(text: '0');
  final _homeLngController = TextEditingController(text: '0');
  final _guardianIdController = TextEditingController();

  // ✅ FCM 토큰 자동 발급받기 (UI 제거)
  String? _fcmToken;

  // ✅ 성별(백엔드 필수)
  String _gender = 'Male'; // 'Male' | 'Female'

  int _role = 1; // 1: 보호자, 2: 대상자
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _getFCMToken(); // ✅ 화면 뜨자마자 토큰 발급
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _birthController.dispose();
    _phoneController.dispose();
    _homeLatController.dispose();
    _homeLngController.dispose();
    _guardianIdController.dispose();
    super.dispose();
  }

  /// ✅ FCM 토큰 자동 발급
  Future<void> _getFCMToken() async {
    try {
      // ⚠️ Android에서는 FCM 토큰 발급(getToken)이 알림 권한과 무관하게 동작합니다.
      // 권한 요청은 여러 화면에서 동시에 호출되면 충돌할 수 있어(“already running”)
      // 회원가입에서는 토큰만 먼저 확보합니다.
      String? token;
      for (int attempt = 1; attempt <= 3; attempt++) {
        token = await FirebaseMessaging.instance.getToken();
        if (token != null && token.isNotEmpty) break;
        await Future.delayed(const Duration(milliseconds: 300));
      }

      if (!mounted) return;
      setState(() => _fcmToken = token);

      debugPrint('🔑 [회원가입] FCM 토큰 발급(getToken): $token');
    } catch (e) {
      debugPrint('❌ [회원가입] FCM 토큰 발급 실패: $e');
    }
  }

  bool _isValidBirth(String birth) {
    final v = birth.trim();
    if (v.length != 8) return false;
    return RegExp(r'^\d{8}$').hasMatch(v);
  }

  Future<void> _onSignupPressed() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final name = _nameController.text.trim();
    final birth = _birthController.text.trim();
    final phone = _phoneController.text.trim();

    if (email.isEmpty ||
        password.isEmpty ||
        name.isEmpty ||
        birth.isEmpty ||
        phone.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('필수 항목을 모두 입력해주세요.')));
      return;
    }

    if (!_isValidBirth(birth)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('생년월일은 YYYYMMDD 형식(8자리)입니다.')),
      );
      return;
    }

    final homeLat = double.tryParse(_homeLatController.text.trim());
    final homeLng = double.tryParse(_homeLngController.text.trim());

    if (homeLat == null || homeLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('집 좌표(homeLat/homeLng)는 숫자로 입력해주세요.')),
      );
      return;
    }

    if (_role == 2 && _guardianIdController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('대상자(role=2)는 guardianId가 필요합니다.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    // ✅ 토큰이 아직 없으면 회원가입 직전에 한 번 더 발급 시도
    if (_fcmToken == null) {
      await _getFCMToken();
    }

    // ✅ 백엔드가 fcmToken을 필수로 요구한다면, null이면 가입 진행을 막아야 DB에 null이 안 들어갑니다.
    if (_fcmToken == null || _fcmToken!.isEmpty) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'FCM 토큰 발급에 실패했습니다. 네트워크/Google Play 서비스 상태 확인 후 다시 시도해주세요.',
          ),
        ),
      );
      return;
    }

    final service = AuthService();
    final ok = await service.signup(
      email: email,
      password: password,
      name: name,
      gender: _gender,
      birth: birth,
      phone: phone,
      homeLat: homeLat,
      homeLng: homeLng,
      role: _role,
      fcmToken: _fcmToken, // ✅ 자동 발급받은 토큰 전송
      guardianId: _guardianIdController.text.trim().isEmpty
          ? null
          : _guardianIdController.text.trim(),
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (!ok) {
      final msg =
          service.lastError ??
          '회원가입 실패! 서버/네트워크를 확인하세요. (${AuthService.baseUrl})';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      return;
    }

    // ✅ Firestore(DB/users/[가입이메일])에 필수 필드 반영 (백엔드 저장 누락 방어)
    try {
      await FirebaseFirestore.instance.collection('users').doc(email).set({
        'fcmToken': _fcmToken,
        'role': _role,
        'gender': _gender,
      }, SetOptions(merge: true));
      debugPrint('✅ [회원가입] Firestore fcmToken 저장 완료: users/$email');
    } catch (e) {
      debugPrint('⚠️ [회원가입] Firestore fcmToken 저장 실패: $e');
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('회원가입 성공! 로그인 해주세요.')));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF37474F),
        elevation: 0,
        title: const Text('회원가입'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              _buildRoleSelector(),
              const SizedBox(height: 16),
              _field(
                _emailController,
                label: '이메일',
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),
              _field(_passwordController, label: '비밀번호', obscureText: true),
              const SizedBox(height: 12),
              _field(_nameController, label: '이름'),
              const SizedBox(height: 12),
              _buildGenderSelector(),
              const SizedBox(height: 12),
              _field(
                _birthController,
                label: '생년월일 (YYYYMMDD)',
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              _field(
                _phoneController,
                label: '전화번호',
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _field(
                      _homeLatController,
                      label: 'homeLat',
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _field(
                      _homeLngController,
                      label: 'homeLng',
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_role == 2) ...[
                _field(_guardianIdController, label: 'guardianId (보호자 UID 등)'),
                const SizedBox(height: 12),
              ],
              // ✅ FCM 토큰은 자동 발급되므로 UI에서 제거
              // 토큰 발급 상태 표시 (선택사항)
              if (_fcmToken != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '✅ FCM 토큰 발급 완료',
                    style: TextStyle(color: Colors.green, fontSize: 12),
                  ),
                ),
              const SizedBox(height: 20),
              SizedBox(
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _onSignupPressed,
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
                          '가입하기',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '※ 백엔드(UserSignup) 모델 필드와 1:1 매칭됩니다.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Color(0xFF78909C)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRoleSelector() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE0E0E0)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Text('역할', style: TextStyle(fontWeight: FontWeight.w600)),
          const Spacer(),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 1, label: Text('보호자')),
              ButtonSegment(value: 2, label: Text('대상자')),
            ],
            selected: <int>{_role},
            onSelectionChanged: (value) {
              setState(() => _role = value.first);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildGenderSelector() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE0E0E0)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Text('성별', style: TextStyle(fontWeight: FontWeight.w600)),
          const Spacer(),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'Male', label: Text('남')),
              ButtonSegment(value: 'Female', label: Text('여')),
            ],
            selected: <String>{_gender},
            onSelectionChanged: (value) {
              setState(() => _gender = value.first);
            },
          ),
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController controller, {
    required String label,
    TextInputType? keyboardType,
    bool obscureText = false,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
