// lib/screens/care_home_main_screen.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'care_home_screen.dart';
import 'settings_screen.dart'; // ★ 1. 진짜 설정 화면 import (이거 꼭 있어야 함)

class CareHomeMainScreen extends StatefulWidget {
  const CareHomeMainScreen({super.key});

  @override
  State<CareHomeMainScreen> createState() => _CareHomeMainScreenState();
}

class _CareHomeMainScreenState extends State<CareHomeMainScreen> {
  int _currentIndex = 0;
  bool _isLinked = false;
  List<Widget> _tabs = [];

  @override
  void initState() {
    super.initState();
    _checkLinkStatus();
  }

  Future<void> _checkLinkStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final seniorCode = prefs.getString('caremode_senior_code');
    if (mounted) {
      setState(() {
        _isLinked = seniorCode != null && seniorCode.isNotEmpty;
        _updateTabs();
      });
    }
  }

  void _updateTabs() {
    _tabs = [
      HomeTab(),
      if (_isLinked) ChatbotTab(),
      DiaryTab(),
      LocationTab(),
      const SettingsScreen(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (_tabs.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      body: _tabs[_currentIndex],
      bottomNavigationBar: _buildModernNavigationBar(),
    );
  }

  Widget _buildModernNavigationBar() {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 13),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(0, Icons.home_rounded, '홈', scheme, isDark),
              if (_isLinked)
                _buildNavItem(
                  1,
                  Icons.chat_bubble_rounded,
                  '챗봇',
                  scheme,
                  isDark,
                ),
              _buildNavItem(
                _isLinked ? 2 : 1,
                Icons.note_alt_rounded,
                '일지',
                scheme,
                isDark,
              ),
              _buildNavItem(
                _isLinked ? 3 : 2,
                Icons.location_on_rounded,
                '위치',
                scheme,
                isDark,
              ),
              _buildNavItem(
                _isLinked ? 4 : 3,
                Icons.settings_rounded,
                '설정',
                scheme,
                isDark,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(
    int index,
    IconData icon,
    String label,
    ColorScheme scheme,
    bool isDark,
  ) {
    final isSelected = _currentIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(
          horizontal: isSelected ? 16 : 12,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? scheme.primary.withValues(alpha: 38)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 24,
              color: isSelected ? scheme.primary : Colors.grey,
            ),
            if (isSelected) ...[
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: scheme.primary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class HomeTab extends StatelessWidget {
  const HomeTab({super.key});

  @override
  Widget build(BuildContext context) => CareHomeScreen();
}

// 🎤 제미나이 라이브 스타일 음성 챗봇
class ChatbotTab extends StatefulWidget {
  const ChatbotTab({super.key});

  @override
  State<ChatbotTab> createState() => _ChatbotTabState();
}

class _ChatbotTabState extends State<ChatbotTab> with TickerProviderStateMixin {
  bool _isListening = false;
  bool _isProcessing = false;
  String _userSpeech = '';
  String _aiResponse = '';

  late AnimationController _waveController;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  final List<String> _conversationHistory = [];

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _waveController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _toggleListening() {
    setState(() {
      if (_isListening) {
        // 멈춤 - 질문 처리
        _isListening = false;
        _isProcessing = true;
        _processVoiceInput();
      } else {
        // 시작
        _isListening = true;
        _isProcessing = false;
        _userSpeech = '';
        _aiResponse = '';
      }
    });
  }

  void _processVoiceInput() {
    // TODO: 실제 음성인식 결과를 여기서 처리
    // speech_to_text 패키지 연동

    // 임시 데모 - 3초 후 샘플 응답
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      setState(() {
        _userSpeech = "오늘 날씨 어때?";
      });
    });

    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _aiResponse = "오늘은 맑고 화창한 날씨입니다. 기온은 15도로 쾌적해요!";
        _conversationHistory.add("나: $_userSpeech");
        _conversationHistory.add("AI: $_aiResponse");
      });

      // TTS로 응답 읽어주기
      // TODO: flutter_tts 연동
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF0A0A0A)
          : const Color(0xFFF8F9FE),
      body: Stack(
        children: [
          // 배경 그라데이션
          _buildBackgroundGradient(isDark),

          // 메인 컨텐츠
          SafeArea(
            child: Column(
              children: [
                _buildHeader(isDark),
                Expanded(child: _buildMainContent(isDark)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackgroundGradient(bool isDark) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: _isListening
              ? (isDark
                    ? [
                        const Color(0xFF1A1A2E),
                        const Color(0xFF16213E),
                        const Color(0xFF0F3460),
                      ]
                    : [
                        const Color(0xFFE3F2FD),
                        const Color(0xFFBBDEFB),
                        const Color(0xFF90CAF9),
                      ])
              : (isDark
                    ? [const Color(0xFF0A0A0A), const Color(0xFF1A1A1A)]
                    : [const Color(0xFFF8F9FE), const Color(0xFFEEF1FF)]),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF667EEA).withValues(alpha: 77),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              Icons.auto_awesome,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AI 음성 대화',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                Text(
                  _isListening
                      ? '듣고 있어요...'
                      : _isProcessing
                      ? '생각 중...'
                      : '버튼을 눌러 대화를 시작하세요',
                  style: TextStyle(
                    fontSize: 13,
                    color: _isListening
                        ? const Color(0xFF4CAF50)
                        : Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent(bool isDark) {
    return Column(
      children: [
        // 대화 내역
        if (_conversationHistory.isNotEmpty)
          Expanded(
            flex: 1,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: _conversationHistory.length,
              itemBuilder: (context, index) {
                final message = _conversationHistory[index];
                final isUser = message.startsWith('나:');
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Align(
                    alignment: isUser
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.75,
                      ),
                      decoration: BoxDecoration(
                        gradient: isUser
                            ? const LinearGradient(
                                colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                              )
                            : null,
                        color: isUser
                            ? null
                            : (isDark ? const Color(0xFF252525) : Colors.white),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 13),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Text(
                        message.substring(message.indexOf(':') + 2),
                        style: TextStyle(
                          fontSize: 15,
                          color: isUser
                              ? Colors.white
                              : (isDark ? Colors.white : Colors.black87),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

        // 메인 버튼 영역
        Expanded(
          flex: 2,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 음성 버튼
                _buildVoiceButton(isDark),

                const SizedBox(height: 40),

                // 텍스트 표시
                if (_userSpeech.isNotEmpty || _aiResponse.isNotEmpty)
                  _buildTextDisplay(isDark),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVoiceButton(bool isDark) {
    return GestureDetector(
      onTap: _isProcessing ? null : _toggleListening,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 외곽 웨이브 (듣는 중일 때만)
          if (_isListening) ...[
            _buildWaveRing(200, 0.0, isDark),
            _buildWaveRing(240, 0.3, isDark),
            _buildWaveRing(280, 0.6, isDark),
          ],

          // 메인 버튼
          ScaleTransition(
            scale: _isListening ? _pulseAnimation : AlwaysStoppedAnimation(1.0),
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: _isListening
                      ? [const Color(0xFF4CAF50), const Color(0xFF66BB6A)]
                      : _isProcessing
                      ? [const Color(0xFFFF9800), const Color(0xFFFFA726)]
                      : [const Color(0xFF667EEA), const Color(0xFF764BA2)],
                ),
                boxShadow: [
                  BoxShadow(
                    color:
                        (_isListening
                                ? const Color(0xFF4CAF50)
                                : const Color(0xFF667EEA))
                            .withValues(alpha: 102),
                    blurRadius: 30,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: Icon(
                _isListening
                    ? Icons.mic
                    : _isProcessing
                    ? Icons.hourglass_empty
                    : Icons.mic_none,
                size: 70,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWaveRing(double size, double delay, bool isDark) {
    return AnimatedBuilder(
      animation: _waveController,
      builder: (context, child) {
        final value = (_waveController.value + delay) % 1.0;
        return Container(
          width: size * (0.5 + value * 0.5),
          height: size * (0.5 + value * 0.5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: const Color(0xFF4CAF50).withValues(
                alpha: ((0.3 * (1 - value)) * 255).clamp(0.0, 255.0).toDouble(),
              ),
              width: 2.0,
            ),
          ),
        );
      },
    );
  }

  Widget _buildTextDisplay(bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 30),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 26),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          if (_userSpeech.isNotEmpty) ...[
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF667EEA).withValues(alpha: 26),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.person,
                    size: 16,
                    color: Color(0xFF667EEA),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _userSpeech,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
            if (_aiResponse.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),
            ],
          ],
          if (_aiResponse.isNotEmpty)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4CAF50).withValues(alpha: 26),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.auto_awesome,
                    size: 16,
                    color: Color(0xFF4CAF50),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _aiResponse,
                    style: TextStyle(
                      fontSize: 16,
                      color: isDark ? Colors.white : Colors.black87,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class DiaryTab extends StatelessWidget {
  const DiaryTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('케어 일지'),
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
      ),
      body: const Center(child: Text('케어 일지 준비 중')),
    );
  }
}

class LocationTab extends StatelessWidget {
  const LocationTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('위치'),
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
      ),
      body: const Center(child: Text('위치 기능 준비 중')),
    );
  }
}

class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('설정'),
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
      ),
      body: const Center(child: Text('설정 기능 준비 중')),
    );
  }
}
