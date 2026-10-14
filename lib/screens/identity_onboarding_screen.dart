// lib/screens/identity_onboarding_screen.dart
import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:permission_handler/permission_handler.dart';

import '../services/identity_upload_service.dart';
import 'package:record/record.dart' as record_pkg;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path_provider/path_provider.dart'; // TODO: pubspec.yaml에 path_provider 추가 필요
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';

import 'permission_screen.dart';

/// 간단한 3단계 본인 확인 온보딩
/// 1) 안내문 노출
/// 2) 마이크로 제시어 읽기(10초 카운트)
/// 3) 전면 카메라로 여러 각도 촬영(최소 3장 권장)
class IdentityOnboardingScreen extends StatefulWidget {
  const IdentityOnboardingScreen({super.key});

  @override
  State<IdentityOnboardingScreen> createState() =>
      _IdentityOnboardingScreenState();
}

class _IdentityOnboardingScreenState extends State<IdentityOnboardingScreen> {
  final record_pkg.AudioRecorder _recorder = record_pkg.AudioRecorder();
  String? _seniorCode; // 연결코드 캐싱
  String? _audioPath;
  bool _isUploadingAudio = false;
  int _step = 0;
  bool _isRecordingPhrase = false;
  double _micProgress = 0;
  Timer? _micTimer;

  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  bool _cameraLoading = false;
  final List<XFile> _captures = [];
  final ImagePicker _imagePicker = ImagePicker();

  _PhotoSource _photoSource = _PhotoSource.camera;
  final TextEditingController _personController = TextEditingController();
  bool _uploading = false;
  String? _uploadResult;

  static const Duration _micTotal = Duration(seconds: 10);
  static const List<String> _suggestedAngles = [
    "정면",
    "왼쪽 45°",
    "오른쪽 45°",
  ]; // 안내용

  static const int _maxGalleryImages = 6;

  @override
  void initState() {
    super.initState();
    _loadSeniorCode();
    _checkOnboardingFlag();
  }

  Future<void> _checkOnboardingFlag() async {
    final prefs = await SharedPreferences.getInstance();
    final onboardingDone = prefs.getBool('caremode_onboarding_done') ?? false;
    if (onboardingDone && mounted) {
      Future.microtask(() {
        if (mounted) Navigator.of(context).pop(true);
      });
    }
  }

  Future<void> _loadSeniorCode() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString('caremode_senior_code');
    if (code != null && code.trim().isNotEmpty) {
      if (mounted) {
        setState(() {
          _seniorCode = code.trim();
        });
      }
    }
  }

  @override
  void dispose() {
    _micTimer?.cancel();
    _cameraController?.dispose();
    _personController.dispose();
    super.dispose();
  }

  Future<void> _requestMicAndStart() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) return;
    await _startMicRecording();
    _startMicCountdown();
  }

  Future<void> _startMicRecording() async {
    final hasPermission = await _recorder.hasPermission();
    if (hasPermission) {
      Directory tempDir = await getTemporaryDirectory();
      String filePath =
          '${tempDir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
        record_pkg.RecordConfig(
          encoder: record_pkg.AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: filePath,
      );
      if (mounted) {
        setState(() {
          _audioPath = filePath;
        });
      }
    }
  }

  Future<void> _stopMicRecording() async {
    final path = await _recorder.stop();
    if (path != null && path.isNotEmpty) {
      if (mounted) {
        setState(() {
          _audioPath = path;
        });
      }
    }
  }

  void _startMicCountdown() {
    _micTimer?.cancel();
    if (mounted) {
      setState(() {
        _isRecordingPhrase = true;
        _micProgress = 0;
      });
    }
    const tick = Duration(milliseconds: 100);
    _micTimer = Timer.periodic(tick, (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _micProgress += tick.inMilliseconds / _micTotal.inMilliseconds;
        if (_micProgress >= 1.0) {
          _micProgress = 1.0;
          _isRecordingPhrase = false;
          timer.cancel();
          _stopMicRecording();
        }
      });
    });
  }

  Future<void> _ensureCameraReady() async {
    if (_cameraController != null && _cameraController!.value.isInitialized) {
      return;
    }
    if (mounted) setState(() => _cameraLoading = true);
    try {
      final cameras = await availableCameras();
      if (!mounted) return;
      _cameras = cameras;
      final front = _cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras.first,
      );
      final ctrl = CameraController(
        front,
        ResolutionPreset.max,
        enableAudio: false,
      );
      await ctrl.initialize();
      if (mounted) {
        setState(() {
          _cameraController = ctrl;
        });
      }
    } catch (e) {
      debugPrint('카메라 초기화 실패: $e');
    } finally {
      if (mounted) setState(() => _cameraLoading = false);
    }
  }

  Future<void> _capture() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }
    try {
      final shot = await _cameraController!.takePicture();
      if (mounted) {
        setState(() {
          _captures.add(shot);
        });
      }
    } catch (e) {
      debugPrint('사진 촬영 실패: $e');
    }
  }

  void _goNextStep() {
    setState(() {
      _step = (_step + 1).clamp(0, 2);
    });
    if (_step == 2) {
      if (_photoSource == _PhotoSource.camera) {
        _ensureCameraReady();
      }
    }
  }

  Future<void> _setPhotoSource(_PhotoSource source) async {
    if (_photoSource == source) return;
    setState(() {
      _photoSource = source;
      _uploadResult = null;
    });
    if (source == _PhotoSource.camera) {
      await _ensureCameraReady();
    } else {
      await _disposeCamera();
    }
  }

  Future<void> _disposeCamera() async {
    final ctrl = _cameraController;
    _cameraController = null;
    if (ctrl != null) {
      try {
        await ctrl.dispose();
      } catch (_) {}
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      // Android 13+는 Photo Picker로 권한 없이 동작하는 경우가 많지만,
      // 구형 기기 대비로 권한 요청을 시도(거부되어도 picker가 뜰 수 있음)
      await Permission.photos.request();
      await Permission.storage.request();

      final List<XFile> picked = await _imagePicker.pickMultiImage(
        imageQuality: 100,
      );
      if (picked.isEmpty) return;

      setState(() {
        final remain = (_maxGalleryImages - _captures.length).clamp(0, 999);
        _captures.addAll(picked.take(remain));
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('갤러리 선택 실패: $e')));
    }
  }

  void _clearCaptures() {
    setState(() {
      _captures.clear();
      _uploadResult = null;
    });
  }

  Future<void> _skipPhotoOnboarding() async {
    if (_uploading) return;
    setState(() {
      _captures.clear();
      _uploadResult = null;
      _personController.clear();
    });
    await _disposeCamera();
    if (!mounted) return;
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => PermissionScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('본인 확인 준비')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: _buildStep(),
        ),
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case 0:
        return _buildIntro();
      case 1:
        return _buildMic();
      case 2:
      default:
        return _buildCamera();
    }
  }

  Widget _buildIntro() {
    return Column(
      key: const ValueKey('intro'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '시작 전에',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        const Text('간단한 음성/얼굴 캡처로 사용자 확인을 진행합니다. 약 1분 내외로 완료됩니다.'),
        const Spacer(),
        FilledButton(onPressed: _goNextStep, child: const Text('시작하기')),
      ],
    );
  }

  Widget _buildMic() {
    return Column(
      key: const ValueKey('mic'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '제시어를 읽어주세요',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text('10초 동안 아래 문장을 또박또박 읽어주세요. (예: "오늘도 좋은 하루 되세요")'),
        const SizedBox(height: 24),
        LinearProgressIndicator(value: _micProgress),
        const SizedBox(height: 16),
        Text(_isRecordingPhrase ? '녹음 중...' : '녹음 시작 버튼을 눌러주세요'),
        const Spacer(),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _isRecordingPhrase ? null : _goNextStep,
                child: const Text('건너뛰기'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: _isRecordingPhrase ? null : _requestMicAndStart,
                child: Text(_isRecordingPhrase ? '진행 중' : '녹음 시작'),
              ),
            ),
            const SizedBox(width: 12),
            // 녹음이 끝났고 오디오 파일이 있을 때만 '다음' 버튼 활성화
            if (!_isRecordingPhrase && _audioPath != null)
              Expanded(
                child: FilledButton(
                  onPressed: _goNextStep,
                  child: const Text('다음'),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: (_audioPath == null || _isUploadingAudio)
              ? null
              : _uploadAudioToServer,
          icon: const Icon(Icons.cloud_upload),
          label: Text(_isUploadingAudio ? '업로드 중...' : '서버로 전송'),
        ),
      ],
    );
  }

  Future<void> _uploadAudioToServer() async {
    if (_audioPath == null) return;
    setState(() => _isUploadingAudio = true);
    try {
      // 연결코드 우선 사용, 없으면 unknown
      final userCode = _seniorCode ?? "unknown";
      final fileName =
          'voice_${userCode}_${DateTime.now().millisecondsSinceEpoch}.m4a';
      final storageRef = FirebaseStorage.instance.ref().child(
        'users_recognition/$fileName',
      );
      final file = File(_audioPath!);
      await storageRef.putFile(file);
      await storageRef.getDownloadURL();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('음성 업로드 완료!')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('업로드 실패: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingAudio = false);
    }
  }

  Widget _buildCamera() {
    final ctrl = _cameraController;
    final needMore = _captures.length < 3;
    final canUpload =
        _personController.text.trim().isNotEmpty && _captures.isNotEmpty;
    return Column(
      key: const ValueKey('camera'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '얼굴을 촬영하세요',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text('권장 각도: ${_suggestedAngles.join(', ')}'),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => _setPhotoSource(_PhotoSource.camera),
                style: OutlinedButton.styleFrom(
                  backgroundColor: _photoSource == _PhotoSource.camera
                      ? Colors.black12
                      : null,
                ),
                child: const Text('카메라 촬영'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton(
                onPressed: () => _setPhotoSource(_PhotoSource.gallery),
                style: OutlinedButton.styleFrom(
                  backgroundColor: _photoSource == _PhotoSource.gallery
                      ? Colors.black12
                      : null,
                ),
                child: const Text('사진 업로드'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(12),
            ),
            child: _photoSource == _PhotoSource.gallery
                ? const Center(
                    child: Text(
                      '갤러리에서 사진을 선택하세요',
                      style: TextStyle(color: Colors.white),
                    ),
                  )
                : _cameraLoading
                ? const Center(child: CircularProgressIndicator())
                : (ctrl != null && ctrl.value.isInitialized)
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: CameraPreview(ctrl),
                  )
                : const Center(
                    child: Text(
                      '카메라를 불러오는 중입니다...',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _captures.isEmpty ? null : _clearCaptures,
                child: const Text('선택 초기화'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: _photoSource == _PhotoSource.gallery
                    ? _pickFromGallery
                    : (_cameraLoading ? null : _capture),
                child: Text(
                  _photoSource == _PhotoSource.gallery ? '갤러리 선택' : '촬영',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: List.generate(
            _captures.length,
            (i) => Chip(label: Text('${i + 1}번 완료')),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _personController,
          decoration: const InputDecoration(
            labelText: '등록할 사용자 ID (예: KimMinJi)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        if (_uploadResult != null)
          Text(
            _uploadResult!,
            style: TextStyle(
              color: _uploadResult!.contains('성공') ? Colors.green : Colors.red,
            ),
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _uploading ? null : _skipPhotoOnboarding,
                child: const Text('나중에 하기'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton(
                onPressed: needMore
                    ? null
                    : () => Navigator.of(context).pop(true),
                child: Text(needMore ? '3장 이상 촬영 후 완료' : '완료'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: (_uploading || !canUpload) ? null : _uploadToServer,
          icon: _uploading
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.cloud_upload),
          label: Text(_uploading ? '업로드 중...' : '서버로 전송'),
        ),
      ],
    );
  }

  Future<void> _uploadToServer() async {
    final personId = _personController.text.trim();
    if (personId.isEmpty || _captures.isEmpty) return;
    if (mounted) {
      setState(() {
        _uploading = true;
        _uploadResult = null;
      });
    }

    // Firebase Storage로 업로드 (주 저장소)
    final result = await IdentityUploadService.uploadFacePhotos(
      userCode: personId,
      photos: List<XFile>.from(_captures),
      onProgress: (current, total, progress) {
        debugPrint(
          '📸 얼굴 사진 업로드: $current/$total - ${progress.toStringAsFixed(0)}%',
        );
      },
    );

    if (!mounted) return;

    final isSuccess = result['success'] == true;
    final msg = isSuccess ? result['message'] : result['error'];

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg ?? '알 수 없는 오류'),
        backgroundColor: isSuccess ? Colors.green : Colors.red,
      ),
    );
    if (mounted) {
      setState(() {
        _uploading = false;
        _uploadResult = msg;
      });
    }

    // AI 서버에도 병렬 전송 (선택적 - 서버 살아있을 때)
    // try {
    //   await FaceService.registerFace(
    //     personId: personId,
    //     photos: List<XFile>.from(_captures),
    //   );
    // } catch (e) {
    //   debugPrint('AI 서버 전송 실패 (무시): $e');
    // }
  }
}

enum _PhotoSource { camera, gallery }
