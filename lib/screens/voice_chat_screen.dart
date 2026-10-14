import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sound_stream/sound_stream.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:intl/intl.dart';

class VoiceChatScreen extends StatefulWidget {
  const VoiceChatScreen({super.key});

  @override
  State<VoiceChatScreen> createState() => _VoiceChatScreenState();
}

class _VoiceChatScreenState extends State<VoiceChatScreen>
    with SingleTickerProviderStateMixin {
  // 서버 주소 (환경 변수 지원 + 기본값 로컬)
  final String _serverUrl = const String.fromEnvironment(
    'VOICE_CHAT_SERVER_URL',
    defaultValue: 'ws://10.0.2.2:8000/ws/chat/20260105_003',
  );

  // ✨ Native AudioManager 제어용 MethodChannel
  static const platform = MethodChannel('com.example.caremode/audio');

  WebSocketChannel? _channel;
  final RecorderStream _recorder = RecorderStream();
  final PlayerStream _player = PlayerStream();

  bool _isConnected = false;
  bool _isMicOn = false;
  bool _isInitializing = true;
  double _volume = 0.5; // 음량 (0.0 ~ 1.0)
  final List<Map<String, dynamic>> _messages = [];
  final ScrollController _scrollController = ScrollController();

  StreamSubscription? _recorderSubscription;
  StreamSubscription? _playerSubscription;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _initApp();
  }

  // ✨ Native에서 현재 시스템 음량 가져오기
  Future<void> _initVolumeFromNative() async {
    try {
      final double? volume = await platform.invokeMethod('getVolume');
      if (volume != null && mounted) {
        setState(() => _volume = volume);
        debugPrint('🔊 Native 음량 초기화: ${(volume * 100).round()}%');
      }
    } catch (e) {
      debugPrint('❌ Native 음량 가져오기 실패: $e');
    }
  }

  Future<void> _initApp() async {
    var status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      _showError("마이크 권한이 필요합니다.");
      setState(() => _isInitializing = false);
      return;
    }

    try {
      await _recorder.initialize(sampleRate: 16000, showLogs: true);
      await _player.initialize(sampleRate: 24000, showLogs: true);
      await _player.start();
      debugPrint('🔊 스피커 시작 완료 - Native AudioManager 제어 활성화');
      _connectToServer();
    } catch (e) {
      _showError("오디오 초기화 실패: $e");
      setState(() => _isInitializing = false);
    }
  }

  void _connectToServer() {
    try {
      _channel = WebSocketChannel.connect(Uri.parse(_serverUrl));

      _channel!.stream.listen(
        (data) {
          debugPrint('📩 WebSocket 데이터 수신: ${data.runtimeType}');
          if (data is String) {
            debugPrint("📩 텍스트 수신");
            _handleTextMessage(data);
          } else if (data is List<int>) {
            debugPrint('📩 오디오 수신: ${data.length} bytes');
            try {
              // 시스템 음량에 의존 (원본 데이터 그대로 사용)
              _player.writeChunk(Uint8List.fromList(data));
              debugPrint('🔊 스피커로 전송 완료');
            } catch (e) {
              debugPrint('❌ 오디오 재생 실패: $e');
              _showError('오디오 재생 실패: $e');
            }
          }
        },
        onDone: () {
          if (mounted) {
            setState(() => _isConnected = false);
            _showError("서버와 연결이 끊어졌습니다.");
          }
        },
        onError: (error) {
          if (mounted) {
            setState(() => _isConnected = false);
            _showError("연결 오류: $error");
          }
        },
      );

      setState(() {
        _isConnected = true;
        _isInitializing = false;
      });
      _addSystemMessage("🤖 AI 비서와 연결되었습니다.");
    } catch (e) {
      setState(() => _isInitializing = false);
      _showError("연결 실패: $e");
    }
  }

  void _handleTextMessage(String jsonStr) {
    try {
      debugPrint("🔍 JSON 파싱 시도");
      final data = jsonDecode(jsonStr);
      final type = data['type'];
      debugPrint('🔍 메시지 타입: $type');

      if (type == 'text') {
        final content = data['content'] ?? '';
        debugPrint("💬 AI 응답");
        _updateLastAiMessage(content);
      } else if (type == 'status') {
        final text = data['text'] ?? '';
        debugPrint("ℹ️ 상태 메시지");
        _addSystemMessage(text);
      }
    } catch (e) {
      debugPrint("❌ JSON 파싱 오류: $e");
      _showError("서버 응답 파싱 실패: $e");
    }
  }

  // ✨ Native AudioManager로 시스템 음량 설정 (100% 작동 보장)
  Future<void> _setSystemVolume(double volume) async {
    try {
      await platform.invokeMethod('setVolume', {'volume': volume});
      if (mounted) {
        setState(() => _volume = volume);
      }
      debugPrint('🔊 Native 음량 설정 완료: ${(volume * 100).round()}%');
    } catch (e) {
      debugPrint('❌ Native 음량 설정 실패: $e');
      _showError('음량 설정 실패: $e');
    }
  }

  Future<void> _toggleMic() async {
    if (!_isConnected) {
      _showError("서버에 연결되지 않았습니다.");
      return;
    }

    if (_isMicOn) {
      await _recorderSubscription?.cancel();
      await _recorder.stop();
      if (mounted) {
        setState(() => _isMicOn = false);
        _addSystemMessage("🔇 마이크 꺼짐");
      }
    } else {
      int sentCount = 0;
      _recorderSubscription = _recorder.audioStream.listen((data) {
        if (_isConnected) {
          sentCount++;
          if (sentCount % 50 == 0) {
            debugPrint(
              '🎤 오디오 전송 중... ($sentCount chunks, ${data.length} bytes)',
            );
          }
          _channel!.sink.add(data);
        }
      });
      await _recorder.start();
      debugPrint('🎤 마이크 스트리밍 시작');
      if (mounted) {
        setState(() => _isMicOn = true);
        _addSystemMessage("🎤 듣고 있어요...");
      }
    }
  }

  void _addSystemMessage(String text) {
    if (!mounted) return;
    setState(() {
      _messages.add({
        'role': 'system',
        'text': text,
        'timestamp': DateTime.now(),
      });
    });
    _scrollToBottom();
  }

  void _updateLastAiMessage(String chunk) {
    if (!mounted) return;
    setState(() {
      if (_messages.isNotEmpty && _messages.last['role'] == 'ai') {
        _messages.last['text'] += chunk;
      } else {
        _messages.add({
          'role': 'ai',
          'text': chunk,
          'timestamp': DateTime.now(),
        });
      }
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(msg)),
          ],
        ),
        backgroundColor: const Color(0xFFE53935),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // 음량 조절 다이얼로그
  void _showVolumeDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.volume_up, color: Color(0xFF667EEA)),
              SizedBox(width: 12),
              Text('음량 조절'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.volume_down, size: 20),
                  Expanded(
                    child: Slider(
                      value: _volume,
                      min: 0.0,
                      max: 1.0,
                      divisions: 20,
                      label: '${(_volume * 100).round()}%',
                      activeColor: const Color(0xFF667EEA),
                      onChanged: (value) {
                        setDialogState(() => _volume = value);
                        setState(() => _volume = value);
                        _setSystemVolume(value);
                      },
                    ),
                  ),
                  const Icon(Icons.volume_up, size: 20),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '현재 음량: ${(_volume * 100).round()}%',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('닫기'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _recorderSubscription?.cancel();
    _playerSubscription?.cancel();
    _recorder.stop();
    _player.stop();
    _channel?.sink.close();
    _pulseController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF0A0E21)
          : const Color(0xFFF8F9FD),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: isDark ? const Color(0xFF1D1E33) : Colors.white,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.psychology,
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AI 음성 비서',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  '실시간 대화',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
                ),
              ],
            ),
          ],
        ),
        actions: [
          // 음량 조절 버튼
          IconButton(
            icon: Icon(
              _volume == 0
                  ? Icons.volume_off
                  : _volume < 0.5
                  ? Icons.volume_down
                  : Icons.volume_up,
              color: isDark ? Colors.white : Colors.black87,
            ),
            onPressed: () => _showVolumeDialog(context),
          ),
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _isConnected
                  ? Colors.green.withOpacity(0.1)
                  : Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _isConnected ? Colors.green : Colors.red,
                width: 1.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _isConnected ? Colors.green : Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _isConnected ? '연결됨' : '연결 끊김',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _isConnected ? Colors.green : Colors.red,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: _isInitializing
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(
                      theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    '초기화 중...',
                    style: TextStyle(
                      fontSize: 16,
                      color: theme.textTheme.bodyMedium?.color,
                    ),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: _messages.isEmpty
                      ? _buildEmptyState(isDark)
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(16),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            final msg = _messages[index];
                            return _buildMessageBubble(msg, isDark);
                          },
                        ),
                ),
                _buildControlPanel(isDark),
              ],
            ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF667EEA).withOpacity(0.3),
                  blurRadius: 30,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: const Icon(Icons.mic_none, size: 64, color: Colors.white),
          ),
          const SizedBox(height: 32),
          Text(
            '마이크 버튼을 눌러\n대화를 시작하세요',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white70 : Colors.black87,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '실시간으로 음성을 주고받습니다',
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.white38 : Colors.black45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlPanel(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1D1E33) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.08),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: _isMicOn
                  ? const Color(0xFFE53935).withOpacity(0.1)
                  : const Color(0xFF667EEA).withOpacity(0.1),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isMicOn ? Icons.graphic_eq : Icons.mic_off,
                  color: _isMicOn
                      ? const Color(0xFFE53935)
                      : const Color(0xFF667EEA),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  _isMicOn ? '말씀해 주세요...' : '마이크 버튼을 눌러 시작',
                  style: TextStyle(
                    color: _isMicOn
                        ? const Color(0xFFE53935)
                        : const Color(0xFF667EEA),
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: _toggleMic,
            child: AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                return Container(
                  height: 88,
                  width: 88,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: _isMicOn
                        ? const LinearGradient(
                            colors: [Color(0xFFE53935), Color(0xFFC62828)],
                          )
                        : const LinearGradient(
                            colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                          ),
                    boxShadow: [
                      BoxShadow(
                        color:
                            (_isMicOn
                                    ? const Color(0xFFE53935)
                                    : const Color(0xFF667EEA))
                                .withOpacity(
                                  _isMicOn
                                      ? 0.4 + (_pulseController.value * 0.3)
                                      : 0.3,
                                ),
                        blurRadius:
                            20 + (_isMicOn ? _pulseController.value * 15 : 0),
                        spreadRadius:
                            5 + (_isMicOn ? _pulseController.value * 8 : 0),
                      ),
                    ],
                  ),
                  child: Icon(
                    _isMicOn ? Icons.stop_rounded : Icons.mic,
                    color: Colors.white,
                    size: 44,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> msg, bool isDark) {
    final role = msg['role'];
    final isSystem = role == 'system';
    final isAi = role == 'ai';
    final timestamp = msg['timestamp'] as DateTime?;

    if (isSystem) {
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withOpacity(0.05)
                : Colors.black.withOpacity(0.04),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.info_outline,
                size: 14,
                color: isDark ? Colors.white54 : Colors.black54,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  msg['text'],
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white54 : Colors.black54,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Align(
      alignment: isAi ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        child: Column(
          crossAxisAlignment: isAi
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.end,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                gradient: isAi
                    ? null
                    : const LinearGradient(
                        colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                      ),
                color: isAi
                    ? (isDark ? const Color(0xFF1D1E33) : Colors.white)
                    : null,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(20),
                  topRight: const Radius.circular(20),
                  bottomLeft: isAi
                      ? const Radius.circular(4)
                      : const Radius.circular(20),
                  bottomRight: isAi
                      ? const Radius.circular(20)
                      : const Radius.circular(4),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.2 : 0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Text(
                msg['text'],
                style: TextStyle(
                  fontSize: 16,
                  color: isAi
                      ? (isDark ? Colors.white : Colors.black87)
                      : Colors.white,
                  height: 1.5,
                ),
              ),
            ),
            if (timestamp != null)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 4, right: 4),
                child: Text(
                  DateFormat('HH:mm').format(timestamp),
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
