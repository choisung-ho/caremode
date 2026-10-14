// lib/screens/voice_onboarding_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'senior_home_screen.dart';
import '../services/identity_upload_service.dart';

/// 음성 온보딩 화면
/// 사용자 음성을 녹음하여 Firebase Storage에 업로드
class VoiceOnboardingScreen extends StatefulWidget {
  const VoiceOnboardingScreen({super.key});

  @override
  State<VoiceOnboardingScreen> createState() => _VoiceOnboardingScreenState();
}

class _VoiceOnboardingScreenState extends State<VoiceOnboardingScreen> {
  static const String _prefsSeniorCodeKey = 'caremode_senior_code';
  static const int _recordDurationSeconds = 10; // 녹음 시간

  final AudioRecorder _recorder = AudioRecorder();

  bool _isRecording = false;
  bool _isUploading = false;
  double _progress = 0.0;
  Timer? _timer;
  String? _recordedFilePath;
  String? _userCode;
  String? _uploadResult;

  @override
  void initState() {
    super.initState();
    _loadUserCode();
  }

  Future<void> _loadUserCode() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userCode = prefs.getString(_prefsSeniorCodeKey);
    });
    debugPrint('Voice onboarding configuration loaded');
  }

  Future<void> _checkPermissionAndStart() async {
    debugPrint('[DEBUG] 마이크 권한 체크 진입');
    var status = await Permission.microphone.status;
    debugPrint('[DEBUG] 마이크 권한 상태: ${status.isGranted}');
    if (!status.isGranted) {
      status = await Permission.microphone.request();
      debugPrint('[DEBUG] 마이크 권한 요청 결과: ${status.isGranted}');
    }

    if (status.isGranted) {
      debugPrint('[DEBUG] 마이크 권한 허용됨, 녹음 시작 시도');
      await _startRecording();
    } else if (mounted) {
      debugPrint('[DEBUG] 마이크 권한 거부됨, 스낵바 및 설정 이동');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('마이크 권한이 필요합니다'),
          backgroundColor: Colors.orange,
        ),
      );
      openAppSettings();
    }
  }

  Future<void> _startRecording() async {
    debugPrint('[DEBUG] _startRecording 진입');
    try {
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _recordedFilePath = '${tempDir.path}/voice_sample_$timestamp.m4a';

      const config = RecordConfig(
        encoder: AudioEncoder.aacLc,
        sampleRate: 44100,
        bitRate: 128000,
      );

      await _recorder.start(config, path: _recordedFilePath!);

      setState(() {
        _isRecording = true;
        _progress = 0.0;
        _uploadResult = null;
      });

      debugPrint("[DEBUG] 녹음 시작");

      _timer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
        setState(() {
          _progress += 1 / (_recordDurationSeconds * 10);
        });
        if (_progress >= 1.0) {
          _stopRecording();
        }
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('녹음이 시작되었습니다.')));
      }
    } catch (e) {
      debugPrint('❌ 녹음 시작 실패: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('녹음 시작 실패: $e')));
      }
    }
  }

  Future<void> _stopRecording() async {
    debugPrint('[DEBUG] _stopRecording 진입');
    _timer?.cancel();

    try {
      final path = await _recorder.stop();
      debugPrint("[DEBUG] 녹음 완료");

      setState(() {
        _isRecording = false;
        _progress = 1.0;
        _recordedFilePath = path;
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('녹음이 완료되었습니다.')));
      }
    } catch (e) {
      debugPrint('❌ 녹음 중지 실패: $e');
      setState(() {
        _isRecording = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('녹음 중지 실패: $e')));
      }
    }
  }

  Future<void> _uploadVoiceSample() async {
    debugPrint('[DEBUG] _uploadVoiceSample 진입');
    if (_recordedFilePath == null || _userCode == null) {
      debugPrint('[DEBUG] 녹음 파일 또는 사용자 코드 없음');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('녹음 파일이나 사용자 코드가 없습니다'),
          duration: Duration(milliseconds: 800),
        ),
      );
      return;
    }

    final file = File(_recordedFilePath!);
    if (!file.existsSync()) {
      debugPrint('[DEBUG] 녹음 파일이 존재하지 않음');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('녹음 파일을 찾을 수 없습니다'),
          duration: Duration(milliseconds: 800),
        ),
      );
      return;
    }

    debugPrint("[DEBUG] 음성 업로드 함수 진입");
    bool snackBarShown = false;
    setState(() {
      _isUploading = true;
      _uploadResult = null;
    });

    try {
      final result = await IdentityUploadService.uploadVoiceSample(
        userCode: _userCode!,
        audioFile: file,
        onProgress: (progress) {
          debugPrint('🎤 업로드 진행: ${progress.toStringAsFixed(0)}%');
        },
      );

      if (!mounted) return;

      final isSuccess = result['success'] == true;
      final msg = isSuccess ? result['message'] : result['error'];

      setState(() {
        _isUploading = false;
        _uploadResult = msg;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg ?? '알 수 없는 오류'),
          backgroundColor: isSuccess ? Colors.green : Colors.red,
          duration: const Duration(milliseconds: 800),
        ),
      );

      // 성공 시 임시 파일 삭제
      if (isSuccess) {
        try {
          await file.delete();
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('[DEBUG] 음성 업로드 실패: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('업로드 실패: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(milliseconds: 1200),
          ),
        );
        snackBarShown = true;
      }
    } finally {
      debugPrint('[DEBUG] finally 블록 진입, mounted: $mounted');
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
        // 만약 위에서 스낵바가 안 떴으면 여기서라도 띄움
        if (!snackBarShown) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('업로드 결과 알림이 표시되지 않았습니다.')));
        }
      } else {
        debugPrint('[DEBUG] context가 unmounted 상태입니다. 스낵바를 띄울 수 없습니다.');
      }
    }
  }

  void _skipAndContinue() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => const SeniorHomeScreen()),
    );
  }

  void _uploadAndContinue() async {
    debugPrint('[DEBUG] _uploadAndContinue 진입');
    debugPrint('Voice onboarding upload started');
    await _uploadVoiceSample();
    debugPrint("🟡 [DEBUG] 업로드 결과");
    if (_uploadResult != null && _uploadResult!.contains('완료')) {
      debugPrint('[DEBUG] 업로드 성공, SeniorHomeScreen 이동');
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const SeniorHomeScreen()),
        );
      }
    } else {
      debugPrint('[DEBUG] 업로드 실패 또는 결과 없음');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_uploadResult ?? '업로드 결과 없음'),
            backgroundColor: Colors.red,
            duration: const Duration(milliseconds: 1200),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasRecording = _recordedFilePath != null && _progress >= 1.0;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text("목소리 등록"),
        actions: [
          TextButton(onPressed: _skipAndContinue, child: const Text('건너뛰기')),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 헤더
            const Text(
              "목소리를 들려주세요",
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              '$_recordDurationSeconds초 동안 아래 문장을 또박또박 읽어주세요.\n'
              '이 음성은 사용자 인식에 사용됩니다.',
              style: TextStyle(
                fontSize: 14,
                color: scheme.onSurface.withValues(alpha: 179),
              ),
            ),
            const SizedBox(height: 24),

            // 제시어 카드
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Icon(Icons.format_quote, color: scheme.primary, size: 32),
                  const SizedBox(height: 12),
                  Text(
                    '"오늘도 좋은 하루 보내세요.\n저는 케어모드를 사용하는 사용자입니다."',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: scheme.onPrimaryContainer,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),

            const Spacer(),

            // 녹음 상태 표시
            if (_isRecording || hasRecording) ...[
              // 진행률 바
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: _progress,
                  minHeight: 12,
                  backgroundColor: scheme.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  _isRecording
                      ? '녹음 중... ${(_progress * _recordDurationSeconds).toInt()}초'
                      : '녹음 완료! ✅',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: _isRecording ? Colors.red : Colors.green,
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],

            // 업로드 결과
            if (_uploadResult != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _uploadResult!.contains('완료')
                      ? Colors.green.withValues(alpha: 26)
                      : Colors.red.withValues(alpha: 26),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      _uploadResult!.contains('완료')
                          ? Icons.check_circle
                          : Icons.error,
                      color: _uploadResult!.contains('완료')
                          ? Colors.green
                          : Colors.red,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_uploadResult!)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // 버튼들
            if (!hasRecording)
              // 녹음 시작 버튼
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton.icon(
                  onPressed: _isRecording
                      ? null
                      : () {
                          debugPrint('[DEBUG] [UI] 녹음 시작 버튼 onPressed');
                          _checkPermissionAndStart();
                        },
                  icon: Icon(_isRecording ? Icons.mic : Icons.mic_none),
                  label: Text(_isRecording ? "녹음 중..." : "녹음 시작"),
                ),
              )
            else
              // 녹음 완료 후 버튼들
              Column(
                children: [
                  // 다시 녹음
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: _isUploading ? null : _checkPermissionAndStart,
                      icon: const Icon(Icons.refresh),
                      label: const Text("다시 녹음"),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // 업로드 후 계속
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: FilledButton.icon(
                      onPressed: _isUploading ? null : _uploadAndContinue,
                      icon: _isUploading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.cloud_upload),
                      label: Text(_isUploading ? "업로드 중..." : "등록하고 계속하기"),
                    ),
                  ),
                ],
              ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
