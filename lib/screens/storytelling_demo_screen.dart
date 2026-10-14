import 'dart:ui';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';

class StorytellingDemoScreen extends StatefulWidget {
  const StorytellingDemoScreen({super.key});

  @override
  State<StorytellingDemoScreen> createState() => _StorytellingDemoScreenState();
}

class _StorytellingDemoScreenState extends State<StorytellingDemoScreen> {
  ({String cleanText, List<int?> cueStarts}) _parseScriptAndCueStarts(
    String raw,
    int cueCount,
  ) {
    final cueStarts = List<int?>.filled(cueCount, null);
    final tagExp = RegExp(r'<[^>]+>');
    final cueExp = RegExp("<mark\\s+name=['\\\"]cue_(\\d+)['\\\"]\\s*/>");

    final buffer = StringBuffer();
    var lastIndex = 0;

    for (final match in tagExp.allMatches(raw)) {
      if (match.start > lastIndex) {
        buffer.write(raw.substring(lastIndex, match.start));
      }

      final tag = raw.substring(match.start, match.end);
      final cueMatch = cueExp.firstMatch(tag);
      if (cueMatch != null) {
        final idx = int.tryParse(cueMatch.group(1) ?? '');
        if (idx != null && idx >= 0 && idx < cueCount) {
          cueStarts[idx] ??= buffer.length;
        }
      }

      lastIndex = match.end;
    }

    if (lastIndex < raw.length) {
      buffer.write(raw.substring(lastIndex));
    }

    return (cleanText: buffer.toString(), cueStarts: cueStarts);
  }

  // --- [유틸리티 함수] ---
  String? getFirebaseDownloadUrl(String? url) {
    if (url == null) return null;

    final reg = RegExp(r'https://storage.googleapis.com/([^/]+)/(.+)');
    final match = reg.firstMatch(url);
    if (match != null) {
      final bucket = match.group(1);
      final path = match.group(2);
      return 'https://firebasestorage.googleapis.com/v0/b/$bucket/o/${Uri.encodeComponent(path ?? "")}?alt=media';
    }

    if (url.contains('firebasestorage.googleapis.com')) return url;
    if (url.startsWith('gs://')) return null;

    return url;
  }

  Timer? _uiTimer;
  String? ttsUrl;
  String? storyScript;
  String? cleanStoryScript; // 태그 제거된 순수 텍스트
  List<int> _cueTextStarts = [];
  List<int> _cueTextEnds = [];
  List<Map<String, dynamic>> cueSheet = [];
  bool loading = true;
  String loadingStatus = "추억을 불러오고 있어요...";

  late AudioPlayer _audioPlayer;
  int _activeCueIndex = 0;
  List<double> _cueTimes = [];
  Duration _audioPosition = Duration.zero;
  bool _isScrubbing = false;
  double? _scrubPreview;
  bool _isVideoEventActive = false;
  final bool _videoEventsEnabled = true; // 영상 이벤트 활성화
  int? _videoEventIndex;
  Duration _pausedAudioPosition = Duration.zero;
  final Set<int> _videoCompleted = {};
  final Set<int> _callCompleted = {};
  String? _resolvedTtsUrl;
  Duration? _audioDuration;
  late AudioPlayer _callPlayer;
  bool _isCallEventActive = false;
  int? _callEventIndex;
  StreamSubscription<PlayerState>? _callStateSub;
  bool _userPaused = false; // 사용자가 의도적으로 일시정지했는지 추적

  final Map<int, VideoPlayerController> _videoControllers = {};
  final ScrollController _scriptScrollController = ScrollController();
  int _lastCharCount = 0;
  int? _pendingCallIndex; // 다음 큐로 넘어갈 때 실행할 call 인덱스
  int? _pendingVideoIndex; // 다음 큐로 넘어갈 때 실행할 video 인덱스
  int _prevCueIndex = -1; // 이전 큐 인덱스 추적

  @override
  void initState() {
    super.initState();
    // 오디오 끊김 방지를 위한 버퍼 설정
    _audioPlayer = AudioPlayer(
      audioLoadConfiguration: const AudioLoadConfiguration(
        androidLoadControl: AndroidLoadControl(
          minBufferDuration: Duration(seconds: 5),
          maxBufferDuration: Duration(seconds: 20),
          bufferForPlaybackDuration: Duration(milliseconds: 2500),
          bufferForPlaybackAfterRebufferDuration: Duration(seconds: 4),
        ),
      ),
    );
    _callPlayer = AudioPlayer();
    _fetchStoryData();
  }

  Future<void> _fetchStoryData() async {
    try {
      debugPrint('🚀 데이터 불러오기 시작...');

      // 테스트용 하드코딩 ID (추후 사용자/날짜에 맞게 주입)
      const userId = '20260107_001';
      const dateId = '2025-12-25';

      final doc = await FirebaseFirestore.instance
          .collection('vectors')
          .doc(userId)
          .collection('diaries')
          .doc(dateId)
          .get()
          .timeout(const Duration(seconds: 5));

      final data = doc.data();
      if (data != null) {
        List<Map<String, dynamic>> tempCueSheet =
            (data['cue_sheet'] as List?)
                ?.map((e) => Map<String, dynamic>.from(e))
                .toList() ??
            [];

        List<double> cueTimes = [];
        for (var cue in tempCueSheet) {
          cueTimes.add((cue['time_seconds'] as num?)?.toDouble() ?? 0.0);
        }

        String rawScript = data['story_script'] ?? '';
        final parsed = _parseScriptAndCueStarts(rawScript, tempCueSheet.length);
        final cleanScript = parsed.cleanText;

        // cue 마크 기반 텍스트 구간(시작/끝)을 계산해서, 타입라이터가 다음 큐로 새지 않도록 함
        final cueCount = tempCueSheet.length;
        final starts = List<int>.filled(cueCount, 0);
        int lastKnown = 0;
        for (int i = 0; i < cueCount; i++) {
          final v = parsed.cueStarts[i];
          if (v == null) {
            starts[i] = lastKnown;
          } else {
            starts[i] = v;
            lastKnown = v;
          }
        }

        final ends = List<int>.filled(cueCount, cleanScript.length);
        for (int i = 0; i < cueCount; i++) {
          final next = (i + 1 < cueCount) ? starts[i + 1] : cleanScript.length;
          ends[i] = next < starts[i] ? starts[i] : next;
        }

        setState(() {
          ttsUrl = data['tts_url'] ?? '';
          storyScript = rawScript;
          cleanStoryScript = cleanScript;
          _cueTextStarts = starts;
          _cueTextEnds = ends;
          cueSheet = tempCueSheet;
          _cueTimes = cueTimes;
          loading = false;
        });

        _resolvedTtsUrl = getFirebaseDownloadUrl(ttsUrl) ?? ttsUrl;
        _preloadMedia();

        if (_resolvedTtsUrl != null && _resolvedTtsUrl!.isNotEmpty) {
          // ★ [수정 1] 리스너(Listener)를 재생보다 "먼저" 등록!
          // 그래야 재생 시작되는 0.1초의 순간도 놓치지 않고 UI를 그림.
          _audioPlayer.positionStream.listen((pos) {
            if (!mounted) return;
            final newIndex = _getActiveCueIndex(pos);
            final cueChanged = newIndex != _activeCueIndex;

            setState(() {
              _audioPosition = pos;
              _activeCueIndex = newIndex;
            });

            _handleCueChange(newIndex, cueChanged);
            // ★ video 자동 재생 제거 - 오직 _handleCueChange에서만 제어
          });

          _audioPlayer.durationStream.listen((dur) {
            if (!mounted) return;
            if (dur != null) {
              setState(() {
                _audioDuration = dur;
              });
            }
          });

          // 재생 상태 감지해서 멈춰있으면 강제로 켜주는 안전장치
          _audioPlayer.playerStateStream.listen((state) {
            if (!mounted) return;
            if (state.processingState == ProcessingState.ready &&
                !state.playing &&
                !_isVideoEventActive &&
                !_isCallEventActive &&
                !_userPaused) {
              // 사용자가 의도적으로 멈춘 경우는 제외
              // 준비됐는데 안 켜져 있으면 강제 실행
              _audioPlayer.play();
            }
          });

          // ★ [수정 2] 리스너 다 달아놓고 나서 재생 시작!
          await _prepareAndPlayTts(_resolvedTtsUrl!);
        }
      }
    } catch (e) {
      debugPrint('🔥 데이터 불러오기 실패/타임아웃: $e');
      if (mounted) {
        setState(() {
          loadingStatus = "서버 연결 지연 (화면을 먼저 띄웁니다)";
          loading = false;
        });
      }
    }
  }

  Future<VideoPlayerController?> _ensureVideoControllerInitialized(
    int index,
  ) async {
    if (index < 0 || index >= cueSheet.length) return null;

    final existing = _videoControllers[index];
    if (existing != null && existing.value.isInitialized) {
      return existing;
    }

    final cue = cueSheet[index];
    final url = getFirebaseDownloadUrl(cue['resource_url']);
    if (url == null || url.isEmpty) return null;

    final createdNew = existing == null;
    final controller =
        existing ??
        VideoPlayerController.networkUrl(
          Uri.parse(url),
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
        );

    if (createdNew) {
      if (mounted) {
        setState(() {
          _videoControllers[index] = controller;
        });
      } else {
        _videoControllers[index] = controller;
      }
    }

    try {
      await controller.initialize().timeout(const Duration(seconds: 10));
      await controller.setLooping(false);
      await controller.setVolume(1.0);
      return controller;
    } catch (e) {
      if (createdNew) {
        _videoControllers.remove(index);
        try {
          await controller.dispose();
        } catch (_) {}
      }
      debugPrint('비디오 온디맨드 초기화 실패 [$index]: $e');
      return null;
    }
  }

  Future<void> _prepareAndPlayTts(String url) async {
    try {
      final localPath = await _cacheTtsToFile(url);
      Duration? dur;
      if (localPath != null) {
        dur = await _audioPlayer.setFilePath(localPath);
      } else {
        dur = await _audioPlayer.setUrl(url);
      }
      if (dur != null) {
        setState(() {
          _audioDuration = dur;
        });
      }
      await _audioPlayer.play();
    } catch (e) {
      debugPrint('TTS 준비 중 오류: $e');
    }
  }

  Future<String?> _cacheTtsToFile(String url) async {
    try {
      final uri = Uri.parse(url);
      if (uri.scheme == 'file') return uri.toFilePath();

      final dir = await getTemporaryDirectory();
      final fileName = 'tts_${url.hashCode}.mp3';
      final file = File('${dir.path}/$fileName');

      // 이미 캐시된 경우 재사용
      if (await file.exists() && await file.length() > 0) {
        return file.path;
      }

      final client = HttpClient();
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode != 200) {
        debugPrint('TTS 다운로드 실패: ${response.statusCode}');
        return null;
      }

      final bytes = await consolidateHttpClientResponseBytes(response);
      await file.writeAsBytes(bytes);
      return file.path;
    } catch (e) {
      debugPrint('TTS 캐시 오류: $e');
      return null;
    }
  }

  Future<void> _preloadMedia() async {
    if (!mounted) return;
    List<Future<void>> loadTasks = [];

    for (int i = 0; i < cueSheet.length; i++) {
      final cue = cueSheet[i];
      final type = cue['type'];
      final url = getFirebaseDownloadUrl(cue['resource_url']);

      // 아이콘 타입들은 URL이 없어도 통과
      if (type == 'greeting' || type == 'closing' || type == 'call') {
        continue;
      }

      if ((type == 'image' || type == 'video') &&
          (url == null || url.isEmpty)) {
        continue;
      }

      if (type == 'image' && url != null) {
        loadTasks.add(
          precacheImage(
            CachedNetworkImageProvider(url),
            context,
          ).catchError((e) => debugPrint('이미지 로딩 지연 ($i): $e')),
        );
      } else if (type == 'video' && url != null) {
        loadTasks.add(() async {
          try {
            final controller = VideoPlayerController.networkUrl(
              Uri.parse(url),
              videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
            );
            await controller.initialize();
            await controller.setVolume(1.0);
            await controller.setLooping(false);

            if (mounted) {
              setState(() {
                _videoControllers[i] = controller;
              });
            }
          } catch (e) {
            debugPrint('비디오 초기화 실패 [$i]: $e');
          }
        }());
      }
    }
    try {
      await Future.wait(loadTasks);
    } catch (e) {
      debugPrint('미디어 로딩 중 일부 오류: $e');
    }
  }

  void _playVideo(int index) {
    if (index < 0) return;
    if (_isCallEventActive) return; // 통화 이벤트 중에는 영상 재생 금지

    // 이미 한 번 재생 완료한 영상은 다시 재생하지 않음
    if (_videoCompleted.contains(index)) {
      final doneController = _videoControllers[index];
      if (doneController != null && doneController.value.isPlaying) {
        doneController.pause();
      }
      return;
    }

    _videoControllers.forEach((key, controller) {
      if (key == index) {
        if (controller.value.isInitialized && !controller.value.isPlaying) {
          controller.play();
        }
      } else {
        if (controller.value.isPlaying) controller.pause();
      }
    });
  }

  int _getActiveCueIndex(Duration position) {
    double currentSeconds = position.inMilliseconds / 1000.0;

    if (_cueTimes.isEmpty) return 0;
    if (currentSeconds < _cueTimes[0]) return 0;

    for (int i = 0; i < _cueTimes.length; i++) {
      if (i == _cueTimes.length - 1) {
        if (currentSeconds >= _cueTimes[i]) return i;
      } else {
        if (currentSeconds >= _cueTimes[i] &&
            currentSeconds < _cueTimes[i + 1]) {
          return i;
        }
      }
    }
    return 0;
  }

  Future<void> _cancelActiveMediaForSeek() async {
    // Stop video without marking completion so cues can fire again after seeking.
    if (_isVideoEventActive) {
      final idx = _videoEventIndex;
      _resetVideoEventState();
      if (idx != null) {
        final ctrl = _videoControllers[idx];
        if (ctrl != null) {
          await ctrl.pause();
          await ctrl.seekTo(Duration.zero);
        }
      }
    }

    // Stop call audio but do not add to completed set so it can replay if revisited.
    if (_isCallEventActive) {
      _callStateSub?.cancel();
      await _callPlayer.pause();
      await _callPlayer.seek(Duration.zero);
      _resetCallEventState();
    }
  }

  Future<void> _seekToProgress(double ratio) async {
    final duration = _audioDuration ?? _audioPlayer.duration;
    if (duration == null || duration.inMilliseconds == 0) return;

    final clamped = ratio.clamp(0.0, 1.0);
    final targetMs = (duration.inMilliseconds * clamped).round();
    final target = Duration(milliseconds: targetMs);

    await _cancelActiveMediaForSeek();

    await _audioPlayer.seek(target);
    if (!_audioPlayer.playing) {
      _userPaused = false; // seek 후에는 자동 재생
      await _audioPlayer.play();
    }

    setState(() {
      _audioPosition = target;
    });
  }

  void _handleCueChange(int newIndex, bool cueChanged) {
    if (cueSheet.isEmpty || newIndex < 0 || newIndex >= cueSheet.length) {
      return;
    }

    // ★ 큐가 변경되었을 때: 이전 큐에 대기 중인 미디어가 있다면 지금 실행
    if (cueChanged && _prevCueIndex >= 0 && _prevCueIndex < cueSheet.length) {
      final prevCue = cueSheet[_prevCueIndex];
      final prevType = prevCue['type'];
      bool startedPrevEvent = false;

      debugPrint('👀 Cue 변경: $_prevCueIndex -> $newIndex');

      // 이전 큐가 call이었고 대기 중이었다면 지금 실행
      if (prevType == 'call' && _pendingCallIndex == _prevCueIndex) {
        debugPrint('📞 Call 실행: $_prevCueIndex');
        final callUrl = getFirebaseDownloadUrl(prevCue['resource_url']);
        if (callUrl != null &&
            callUrl.isNotEmpty &&
            !_callCompleted.contains(_prevCueIndex)) {
          _startCallEvent(_prevCueIndex, callUrl);
          startedPrevEvent = true;
        }
        _pendingCallIndex = null;
      }

      // 이전 큐가 video였고 대기 중이었다면 지금 실행
      if (prevType == 'video' && _pendingVideoIndex == _prevCueIndex) {
        debugPrint('🎥 Video 실행 시도: $_prevCueIndex');
        if (!_videoCompleted.contains(_prevCueIndex)) {
          debugPrint('🎥 _startVideoEvent 호출');
          _startVideoEvent(_prevCueIndex);
          startedPrevEvent = true;
        } else {
          debugPrint('⚠️ 이미 재생 완료됨');
        }
        _pendingVideoIndex = null;
      }

      // 이전 cue에서 이벤트(영상/통화)를 시작했다면, 현재 cue 처리를 진행하면
      // 아래 로직에서 이벤트가 즉시 리셋되어 영상이 끊기고 TTS가 계속되는 문제가 생길 수 있음.
      // 따라서 이벤트 시작 시점에는 여기서 종료한다.
      if (startedPrevEvent) {
        _prevCueIndex = newIndex;
        return;
      }
    }

    // 현재 큐 처리
    final cue = cueSheet[newIndex];
    final isVideoCue = cue['type'] == 'video';
    final isCallCue = cue['type'] == 'call';
    final callUrl = getFirebaseDownloadUrl(cue['resource_url']);
    final hasCallAudio = isCallCue && callUrl != null && callUrl.isNotEmpty;

    if (!_videoEventsEnabled && isVideoCue) {
      _prevCueIndex = newIndex;
      return; // 이벤트(영상) 중단 모드
    }

    // call 큐: 지금은 대기 상태로 등록만 (아이콘 표시)
    if (hasCallAudio && !_callCompleted.contains(newIndex)) {
      debugPrint('📞 Call 큐 등록 (pending): $newIndex');
      _pendingCallIndex = newIndex;
      _prevCueIndex = newIndex;
      return;
    }

    // video 큐: 지금은 대기 상태로 등록만 (아이콘 표시)
    if (isVideoCue && !_videoCompleted.contains(newIndex)) {
      debugPrint('🎥 Video 큐 등록 (pending): $newIndex');
      _pendingVideoIndex = newIndex;
      _prevCueIndex = newIndex;
      return;
    }

    // 다른 타입의 큐는 기존 로직 유지
    if (cueChanged && _isVideoEventActive) {
      _resetVideoEventState();
      if (!_audioPlayer.playing) {
        _audioPlayer.play();
      }
    } else if (cueChanged && _isCallEventActive) {
      _finishCallEvent();
    }

    _prevCueIndex = newIndex;
  }

  Future<void> _startVideoEvent(int index) async {
    if (!_videoEventsEnabled) return;
    if (_isVideoEventActive && _videoEventIndex == index) return;
    if (_isCallEventActive) return; // 통화 이벤트 진행 중이면 영상 건너뛰기

    _pausedAudioPosition = _audioPlayer.position;

    setState(() {
      _isVideoEventActive = true;
      _videoEventIndex = index;
    });

    await _audioPlayer.pause();

    final controller = await _ensureVideoControllerInitialized(index);
    if (controller == null || !controller.value.isInitialized) {
      await _finishVideoEvent();
      return;
    }

    await controller.setLooping(false);
    await controller.setVolume(1.0);
    await controller.seekTo(Duration.zero);
    await controller.play();

    _attachVideoCompletionListener(controller, index);
    _playVideo(index);
  }

  void _attachVideoCompletionListener(
    VideoPlayerController controller,
    int index,
  ) {
    void listener() {
      final value = controller.value;
      final duration = value.duration;

      if (!_isVideoEventActive || _videoEventIndex != index) return;

      final isAtEnd =
          value.position >= duration - const Duration(milliseconds: 150);

      if (isAtEnd) {
        controller.removeListener(listener);
        _videoCompleted.add(index);
        controller.pause();
        _finishVideoEvent();
      }
    }

    controller.addListener(listener);
  }

  Future<void> _finishVideoEvent() async {
    if (!_isVideoEventActive) return;

    final finishedIndex = _videoEventIndex;
    _resetVideoEventState();

    if (finishedIndex != null) {
      final ctrl = _videoControllers[finishedIndex];
      if (ctrl != null) {
        await ctrl.pause();
        // 볼륨을 0으로 고정하면 다음 재생이 무음이 될 수 있어 그대로 둠
      }
    }

    await _audioPlayer.setVolume(1.0);
    if (_isCallEventActive) return; // 통화 이벤트 중이면 TTS 재개하지 않음
    await _audioPlayer.seek(
      _pausedAudioPosition + const Duration(milliseconds: 50),
    ); // 살짝 앞으로 밀어 끊김 방지
    await Future.delayed(const Duration(milliseconds: 80));
    _userPaused = false; // 이벤트 후에는 자동 재생
    await _audioPlayer.play();
  }

  Future<void> _startCallEvent(int index, String url) async {
    if (_isCallEventActive && _callEventIndex == index) return;
    if (_isVideoEventActive) {
      await _finishVideoEvent();
    }

    _pausedAudioPosition = _audioPlayer.position;

    setState(() {
      _isCallEventActive = true;
      _callEventIndex = index;
    });

    await _audioPlayer.pause();

    try {
      _callStateSub?.cancel();
      await _callPlayer.setUrl(url);
      _callStateSub = _callPlayer.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          _finishCallEvent();
        }
      });
      await _callPlayer.play();
    } catch (e) {
      debugPrint('통화 오디오 재생 오류: $e');
      await _finishCallEvent();
    }
  }

  Future<void> _finishCallEvent() async {
    if (!_isCallEventActive) return;

    _callStateSub?.cancel();
    await _callPlayer.pause();
    await _callPlayer.seek(Duration.zero);

    if (_callEventIndex != null) {
      _callCompleted.add(_callEventIndex!);
    }

    _resetCallEventState();

    // 통화 이벤트 종료 후에만 TTS 재개 (영상 이벤트는 이미 해제됨)
    await _audioPlayer.seek(
      _pausedAudioPosition + const Duration(milliseconds: 50),
    );
    await Future.delayed(const Duration(milliseconds: 80));
    _userPaused = false; // 이벤트 후에는 자동 재생
    await _audioPlayer.play();
  }

  void _resetCallEventState() {
    if (!_isCallEventActive) return;
    if (!mounted) return;
    setState(() {
      _isCallEventActive = false;
      _callEventIndex = null;
    });
  }

  void _resetVideoEventState() {
    if (!_isVideoEventActive) return;
    if (!mounted) return;
    setState(() {
      _isVideoEventActive = false;
      _videoEventIndex = null;
    });
  }

  @override
  void dispose() {
    _uiTimer?.cancel();
    _callStateSub?.cancel();
    _audioPlayer.dispose();
    _callPlayer.dispose();
    _scriptScrollController.dispose();
    for (var controller in _videoControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String? _getCurrentImageUrl() {
    if (cueSheet.isEmpty) return null;
    if (_activeCueIndex < 0 || _activeCueIndex >= cueSheet.length) return null;

    final cue = cueSheet[_activeCueIndex];
    if (cue['type'] == 'image') {
      return getFirebaseDownloadUrl(cue['resource_url']);
    }
    return null;
  }

  // ★ 디자인 상수 정의
  static const _warmCream = Color(0xFFFFF8F0);
  static const _softPeach = Color(0xFFFFE4D6);
  static const _pastelPink = Color(0xFFFFD6E0);
  static const _pastelMint = Color(0xFFD4F0E7);
  static const _pastelLavender = Color(0xFFE8DFF5);
  static const _pastelSky = Color(0xFFD6EEFF);
  static const _deepNavy = Color(0xFF1A1F3C);
  static const _glassWhite = Color(0x1AFFFFFF); // 10% white
  static const _glassBorder = Color(0x4DFFFFFF); // 30% white

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);

    if (loading) {
      return Scaffold(
        backgroundColor: _deepNavy,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 로딩 인디케이터 - 부드러운 글로우 효과
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: _softPeach.withValues(alpha: 77),
                      blurRadius: 30,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: const CircularProgressIndicator(
                  color: _warmCream,
                  strokeWidth: 3,
                ),
              ),
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: _glassWhite,
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: _glassBorder, width: 1),
                ),
                child: Text(
                  loadingStatus,
                  style: TextStyle(
                    color: _warmCream.withValues(alpha: 230),
                    fontSize: 16,
                    fontFamily: 'Pyeongtaek',
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // cueSheet가 있으면 무조건 cue_0을 보여주도록 보장
    final int activeCueIndex = cueSheet.isNotEmpty
        ? _activeCueIndex.clamp(0, cueSheet.length - 1)
        : 0;

    // 이벤트(영상/통화)가 시작되면 TTS 큐 인덱스가 다음으로 넘어가도,
    // 화면 비주얼은 이벤트 cue를 고정해서 보여줘야 함.
    final int visualCueIndex = cueSheet.isNotEmpty
        ? (_isVideoEventActive
              ? (_videoEventIndex ?? activeCueIndex)
              : (_isCallEventActive
                    ? (_callEventIndex ?? activeCueIndex)
                    : activeCueIndex))
        : 0;

    final cue = (cueSheet.isNotEmpty)
        ? cueSheet[visualCueIndex.clamp(0, cueSheet.length - 1)]
        : null;

    final currentImgUrl = _getCurrentImageUrl();

    // ★ cue 타입에 따라 비율 동적 조정
    final cueType = cue?['type'];
    final isImageType = cueType == 'image';
    final isIconType =
        cueType == 'greeting' ||
        cueType == 'call' ||
        cueType == 'closing' ||
        cueType == 'location' ||
        cueType == 'sms';

    // 비율 설정: 아이콘=작게, 이미지=크게, 동영상=최대
    final int visualFlex;
    final int textFlex;
    final bool hideTextBox;

    if (_isVideoEventActive) {
      // 동영상 재생 중: 텍스트 박스 숨기고 최대 비율
      visualFlex = 10;
      textFlex = 0;
      hideTextBox = true;
    } else if (isImageType) {
      // 이미지: 좀 크게
      visualFlex = 6;
      textFlex = 5;
      hideTextBox = false;
    } else if (isIconType) {
      // 아이콘: 작게, 텍스트 크게
      visualFlex = 3;
      textFlex = 6;
      hideTextBox = false;
    } else {
      // 기본값
      visualFlex = 5;
      textFlex = 5;
      hideTextBox = false;
    }

    final duration = _audioDuration ?? _audioPlayer.duration;
    final totalDurationMs = duration?.inMilliseconds ?? 0;
    final currentMs = _audioPosition.inMilliseconds;
    final baseProgress = totalDurationMs > 0
        ? (currentMs / totalDurationMs).clamp(0.0, 1.0)
        : 0.0;
    final progressRatio = _isScrubbing
        ? (_scrubPreview ?? baseProgress)
        : baseProgress;

    return Scaffold(
      backgroundColor: _deepNavy,
      body: Stack(
        children: [
          // 1. 배경 (Blur) - 더 따뜻한 톤
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 800),
            child: Container(
              key: ValueKey(currentImgUrl ?? 'warm_bg'),
              width: double.infinity,
              height: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_deepNavy, const Color(0xFF2D1F3D), _deepNavy],
                ),
                image: currentImgUrl != null
                    ? DecorationImage(
                        image: CachedNetworkImageProvider(currentImgUrl),
                        fit: BoxFit.cover,
                        colorFilter: ColorFilter.mode(
                          _deepNavy.withValues(alpha: 128),
                          BlendMode.darken,
                        ),
                      )
                    : null,
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        _deepNavy.withValues(alpha: 77),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // 2. 메인 컨텐츠 - Bento Grid Style
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  _buildHeader(progressRatio, totalDurationMs),
                  const SizedBox(height: 24),

                  // 비주얼 영역 - 동적 비율
                  Expanded(
                    flex: visualFlex,
                    child: Center(
                      child: Hero(
                        tag: 'visual_card',
                        child: AspectRatio(
                          aspectRatio: 4 / 3,
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(32),
                              // 폴라로이드 프레임 효과
                              border: Border.all(
                                color: _warmCream.withValues(alpha: 102),
                                width: 8,
                              ),
                              boxShadow: [
                                // 부드러운 남색 그림자
                                BoxShadow(
                                  color: _deepNavy.withValues(alpha: 128),
                                  blurRadius: 40,
                                  spreadRadius: 5,
                                  offset: const Offset(0, 15),
                                ),
                                BoxShadow(
                                  color: const Color(
                                    0xFF3D2F5C,
                                  ).withValues(alpha: 77),
                                  blurRadius: 60,
                                  spreadRadius: 10,
                                  offset: const Offset(0, 25),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(24),
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 500),
                                switchInCurve: Curves.easeOutCubic,
                                switchOutCurve: Curves.easeInCubic,
                                child: Container(
                                  key: ValueKey(
                                    'visual_${visualCueIndex}_'
                                    '${_isVideoEventActive ? 'video' : (_isCallEventActive ? 'call' : 'none')}',
                                  ),
                                  child: cue != null
                                      ? _buildVisualContentNew(
                                          visualCueIndex,
                                          cue,
                                        )
                                      : Container(
                                          decoration: const BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: [
                                                _deepNavy,
                                                Color(0xFF2D1F3D),
                                              ],
                                            ),
                                          ),
                                        ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // 텍스트 영역 - 동영상 재생 중에는 숨김
                  if (!hideTextBox)
                    Expanded(
                      flex: textFlex,
                      child: Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          // 어두운 반투명 배경으로 가독성 향상
                          color: _deepNavy.withValues(alpha: 200),
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(color: _glassBorder, width: 1.5),
                          boxShadow: [
                            BoxShadow(
                              color: _deepNavy.withValues(alpha: 150),
                              blurRadius: 30,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(28),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Caption/Now Playing - 파스텔 알약 태그
                                  if (_isCallEventActive ||
                                      (cue != null && cue['caption'] != null))
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        if (cue != null &&
                                            cue['caption'] != null)
                                          _buildPillCaption(cue['caption']),
                                        if (_isCallEventActive)
                                          _buildCallNowPlayingPill(),
                                      ],
                                    ),
                                  if (_isCallEventActive ||
                                      (cue != null && cue['caption'] != null))
                                    const SizedBox(height: 12),
                                  Expanded(child: _buildTypewriterScript()),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(double progress, int totalDurationMs) {
    final sliderValue = _isScrubbing ? (_scrubPreview ?? progress) : progress;
    final canSeek = totalDurationMs > 0;

    return Column(
      children: [
        // 1줄: 뒤로 가기 + 시간 표시 + 재생 버튼
        Row(
          children: [
            // 뒤로 가기 버튼 - 캡슐 모양
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: _glassWhite,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _glassBorder, width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: _warmCream.withValues(alpha: 230),
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '돌아가기',
                      style: TextStyle(
                        color: _warmCream.withValues(alpha: 230),
                        fontSize: 13,
                        fontFamily: 'Pyeongtaek',
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),
            // 시간 표시 - 중앙
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: _glassWhite,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _glassBorder, width: 1),
              ),
              child: Text(
                canSeek
                    ? '${_formatDuration(Duration(milliseconds: (sliderValue * totalDurationMs).round()))} / ${_formatDuration(Duration(milliseconds: totalDurationMs))}'
                    : '--:-- / --:--',
                style: TextStyle(
                  color: _warmCream.withValues(alpha: 217),
                  fontSize: 13,
                  fontFamily: 'Pyeongtaek',
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const Spacer(),
            // 재생/일시정지 버튼 - 네온 글로우
            GestureDetector(
              onTap: () async {
                // 현재 진행 중인 미디어에 맞춰 토글
                if (_isCallEventActive) {
                  if (_callPlayer.playing) {
                    await _callPlayer.pause();
                  } else {
                    await _callPlayer.play();
                  }
                  setState(() {});
                  return;
                }

                if (_isVideoEventActive && _videoEventIndex != null) {
                  final ctrl = _videoControllers[_videoEventIndex!];
                  if (ctrl != null) {
                    if (ctrl.value.isPlaying) {
                      await ctrl.pause();
                    } else {
                      await ctrl.play();
                    }
                    setState(() {});
                  }
                  return;
                }

                // TTS 재생/일시정지
                if (_audioPlayer.playing) {
                  await _audioPlayer.pause();
                  _userPaused = true; // 사용자가 멈춤
                } else {
                  _userPaused = false; // 사용자가 재생
                  await _audioPlayer.play();
                }
                setState(() {});
              },
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      _softPeach.withValues(alpha: 77),
                      _pastelLavender.withValues(alpha: 77),
                    ],
                  ),
                  border: Border.all(color: _glassBorder, width: 1.5),
                  boxShadow: [
                    // 네온 글로우 효과
                    BoxShadow(
                      color: (_computeIsPlaying() ? _pastelPink : _pastelMint)
                          .withValues(alpha: 102),
                      blurRadius: 15,
                      spreadRadius: 2,
                    ),
                    BoxShadow(
                      color: _deepNavy.withValues(alpha: 77),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  _computeIsPlaying()
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  color: _warmCream,
                  size: 22,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // 2줄: 슬라이더 (전체 너비 활용)
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 6,
            activeTrackColor: _softPeach,
            inactiveTrackColor: Colors.white.withValues(alpha: 41),
            thumbColor: _pastelLavender,
            overlayColor: _pastelLavender.withValues(alpha: 56),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
          ),
          child: Slider(
            min: 0,
            max: 1,
            value: sliderValue.clamp(0.0, 1.0),
            onChangeStart: canSeek
                ? (v) {
                    setState(() {
                      _isScrubbing = true;
                      _scrubPreview = v;
                    });
                  }
                : null,
            onChanged: canSeek
                ? (v) {
                    setState(() {
                      _scrubPreview = v;
                    });
                  }
                : null,
            onChangeEnd: canSeek
                ? (v) async {
                    setState(() {
                      _isScrubbing = false;
                      _scrubPreview = null;
                    });
                    await _seekToProgress(v);
                  }
                : null,
          ),
        ),
      ],
    );
  }

  bool _computeIsPlaying() {
    if (_isCallEventActive) {
      return _callPlayer.playing;
    }
    if (_isVideoEventActive && _videoEventIndex != null) {
      final ctrl = _videoControllers[_videoEventIndex!];
      if (ctrl != null) {
        return ctrl.value.isPlaying;
      }
    }
    return _audioPlayer.playing;
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  // ★ [핵심] 여기에 greeting, closing이 누락됐었음. 이제 추가됨!
  Widget _buildVisualContentNew(int index, Map<String, dynamic> cue) {
    switch (cue['type']) {
      case 'greeting':
        // 아침 인사: 해 아이콘 - 따뜻한 파스텔 톤
        return _buildIconVisual(
          Icons.wb_sunny_rounded,
          const Color(0xFFFFB347),
          _softPeach,
        );
      case 'call':
        // 통화: 전화 아이콘 - 민트 톤
        return _buildIconVisual(
          Icons.phone_in_talk_rounded,
          const Color(0xFF7FCCB4),
          _pastelMint,
        );
      case 'sms':
        // 문자: 메일/채팅 아이콘 - 인디고 톤
        return _buildIconVisual(
          Icons.mail_outline_rounded,
          Colors.indigoAccent,
          Colors.indigoAccent.withValues(alpha: 51),
        );
      case 'closing':
        // 마무리: 달/밤 아이콘 - 라벤더 톤
        return _buildIconVisual(
          Icons.nights_stay_rounded,
          const Color(0xFF9B8DC9),
          _pastelLavender,
        );
      case 'location':
        // 장소/이동: 위치 아이콘 - 레드/핑크 포인트
        return _buildIconVisual(
          Icons.location_on_rounded,
          Colors.redAccent,
          const Color(0xFFFFC2C2),
        );
      case 'image':
        final imgUrl = getFirebaseDownloadUrl(cue['resource_url']);
        if (imgUrl != null && imgUrl.isNotEmpty) {
          return Stack(
            fit: StackFit.expand,
            children: [
              CachedNetworkImage(
                imageUrl: imgUrl,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                fadeInDuration: const Duration(milliseconds: 400),
                placeholder: (context, url) => Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [_deepNavy, const Color(0xFF2D1F3D)],
                    ),
                  ),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _glassWhite,
                        shape: BoxShape.circle,
                      ),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _warmCream.withValues(alpha: 153),
                      ),
                    ),
                  ),
                ),
                errorWidget: (context, url, error) => Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [_deepNavy, const Color(0xFF2D1F3D)],
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.photo_outlined,
                        color: _warmCream.withValues(alpha: 102),
                        size: 48,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '사진을 불러올 수 없어요',
                        style: TextStyle(
                          color: _warmCream.withValues(alpha: 128),
                          fontSize: 14,
                          fontFamily: 'Pyeongtaek',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // 사진 위 부드러운 비네트 효과
              Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      Colors.transparent,
                      _deepNavy.withValues(alpha: 38),
                    ],
                    radius: 1.2,
                  ),
                ),
              ),
            ],
          );
        }
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [_deepNavy, const Color(0xFF2D1F3D)],
            ),
          ),
        );
      case 'video':
        // 이벤트 중단 모드에서는 영상 대신 아이콘 표시
        if (!_videoEventsEnabled) {
          return _buildIconVisual(
            Icons.ondemand_video_rounded,
            const Color(0xFF7BA3C9),
            _pastelSky,
          );
        }

        final controller = _videoControllers[index];
        final isActiveVideo =
            _isVideoEventActive &&
            _videoEventIndex == index &&
            controller != null;

        if (isActiveVideo && controller!.value.isInitialized) {
          return FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: controller.value.size.width,
              height: controller.value.size.height,
              child: VideoPlayer(controller),
            ),
          );
        }

        // 재생 대기 상태에서는 아이콘을 노출해 첫 프레임이 미리 보이지 않게 함
        return _buildIconVisual(
          Icons.ondemand_video_rounded,
          const Color(0xFF7BA3C9),
          _pastelSky,
        );
      default:
        // 알 수 없는 타입은 기본 아이콘
        return _buildIconVisual(
          Icons.auto_awesome_rounded,
          const Color(0xFFAAAAAA),
          Colors.grey.shade200,
        );
    }
  }

  // ★ [추가] 아이콘을 그려주는 헬퍼 함수 - Glassmorphism 스타일
  Widget _buildIconVisual(IconData icon, Color iconColor, Color glowColor) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _deepNavy,
            const Color(0xFF2D1F3D),
            _deepNavy.withValues(alpha: 230),
          ],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 외부 글로우 링
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: glowColor.withValues(alpha: 77),
                  blurRadius: 40,
                  spreadRadius: 15,
                ),
              ],
            ),
            child: Container(
              padding: const EdgeInsets.all(35),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _glassWhite,
                border: Border.all(
                  color: glowColor.withValues(alpha: 102),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: iconColor.withValues(alpha: 51),
                    blurRadius: 25,
                    spreadRadius: 5,
                  ),
                  BoxShadow(
                    color: _deepNavy.withValues(alpha: 128),
                    blurRadius: 15,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Icon(
                icon,
                size: 70,
                color: iconColor,
                shadows: [
                  Shadow(
                    color: iconColor.withValues(alpha: 128),
                    blurRadius: 20,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ★ [추가] 파스텔 알약 캡션 태그
  Widget _buildPillCaption(String caption) {
    // 캡션 내용에 따라 색상 결정
    Color bgColor;
    Color textColor;
    IconData prefixIcon;

    if (caption.contains('아침') || caption.contains('인사')) {
      bgColor = _softPeach;
      textColor = const Color(0xFF8B5A2B);
      prefixIcon = Icons.wb_sunny_outlined;
    } else if (caption.contains('통화') || caption.contains('전화')) {
      bgColor = _pastelMint;
      textColor = const Color(0xFF2E7D5A);
      prefixIcon = Icons.phone_outlined;
    } else if (caption.contains('저녁') ||
        caption.contains('밤') ||
        caption.contains('마무리')) {
      bgColor = _pastelLavender;
      textColor = const Color(0xFF5E4A8A);
      prefixIcon = Icons.nights_stay_outlined;
    } else if (caption.contains('사진') || caption.contains('추억')) {
      bgColor = _pastelPink;
      textColor = const Color(0xFF9B4A6A);
      prefixIcon = Icons.photo_camera_outlined;
    } else {
      bgColor = _pastelSky;
      textColor = const Color(0xFF3A6B8C);
      prefixIcon = Icons.auto_awesome_outlined;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor.withValues(alpha: 217),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: bgColor.withValues(alpha: 102),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(prefixIcon, size: 14, color: textColor),
          const SizedBox(width: 6),
          Text(
            caption,
            style: TextStyle(
              color: textColor,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              fontFamily: 'Pyeongtaek',
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  // ★ [추가] 통화 음성 재생 상태 표시 (재생/로딩/일시정지) - StreamBuilder로 실시간 갱신
  Widget _buildCallNowPlayingPill() {
    return StreamBuilder<PlayerState>(
      stream: _callPlayer.playerStateStream,
      builder: (context, snapshot) {
        final state = snapshot.data ?? _callPlayer.playerState;

        String label;
        bool isPlaying = false;
        bool isLoading = false;

        if (state.processingState == ProcessingState.loading ||
            state.processingState == ProcessingState.buffering) {
          label = '통화 음성 불러오는 중…';
          isLoading = true;
        } else if (state.playing) {
          label = '통화 음성 재생 중';
          isPlaying = true;
        } else {
          label = '통화 음성 일시정지';
        }

        const textColor = Color(0xFF2E7D5A);
        final bgColor = _pastelMint;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: bgColor.withValues(alpha: 217),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: bgColor.withValues(alpha: isPlaying ? 153 : 102),
                blurRadius: isPlaying ? 15 : 10,
                spreadRadius: isPlaying ? 2 : 1,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 로딩 중일 때는 로딩 아이콘
              if (isLoading)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: textColor,
                  ),
                )
              // 재생 중일 때는 파형 애니메이션
              else if (isPlaying)
                _AudioWaveform(isPlaying: true, color: textColor)
              // 일시정지일 때는 정지된 파형
              else
                _AudioWaveform(isPlaying: false, color: textColor),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: textColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Pyeongtaek',
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTypewriterScript() {
    return StreamBuilder<Duration>(
      stream: _audioPlayer.positionStream,
      builder: (context, snapshot) {
        final scriptText = cleanStoryScript ?? '';
        if (scriptText.isEmpty) return const SizedBox();

        final duration = _audioDuration ?? _audioPlayer.duration;
        if (duration == null || duration.inMilliseconds <= 0) {
          return const SizedBox();
        }

        final position = snapshot.data ?? _audioPlayer.position;
        final currentSeconds = position.inMilliseconds / 1000.0;
        final totalSeconds = duration.inMilliseconds / 1000.0;

        // cue 마크(<mark name='cue_n'/>) 기준으로 텍스트를 구간화해서,
        // 현재 cue의 끝을 넘어서 다음 cue 텍스트가 미리 보이지 않게 함.
        int charCount;
        final cueCount = cueSheet.length;
        final hasCueRanges =
            _cueTextStarts.length == cueCount &&
            _cueTextEnds.length == cueCount;
        final hasCueTimes = _cueTimes.length == cueCount;

        if (cueCount > 0 && hasCueRanges && hasCueTimes) {
          final idx = _activeCueIndex.clamp(0, cueCount - 1);
          final startOffset = _cueTextStarts[idx].clamp(0, scriptText.length);
          final endOffset = _cueTextEnds[idx].clamp(0, scriptText.length);

          final cueStart = _cueTimes[idx];
          final cueEnd = (idx + 1 < _cueTimes.length)
              ? _cueTimes[idx + 1]
              : totalSeconds;

          final span = (cueEnd - cueStart);
          final local = span > 0
              ? ((currentSeconds - cueStart) / span).clamp(0.0, 1.0)
              : (currentSeconds >= cueEnd ? 1.0 : 0.0);

          final within = ((endOffset - startOffset) * local).floor();
          charCount = (startOffset + within).clamp(0, scriptText.length);
        } else {
          // fallback: 전체 길이 비례(기존 방식)
          final progress = totalSeconds > 0
              ? (currentSeconds / totalSeconds).clamp(0.0, 1.0)
              : 0.0;
          charCount = (progress * scriptText.length).toInt();
        }

        final visibleScript = scriptText.substring(0, charCount);

        // ★ 글자가 추가될 때마다 자동 스크롤
        if (charCount > _lastCharCount) {
          _lastCharCount = charCount;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scriptScrollController.hasClients) {
              _scriptScrollController.animateTo(
                _scriptScrollController.position.maxScrollExtent,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            }
          });
        } else if (charCount < _lastCharCount) {
          // 되감기/시크 시에는 현재 값으로 동기화
          _lastCharCount = charCount;
        }

        return SingleChildScrollView(
          controller: _scriptScrollController,
          physics: const BouncingScrollPhysics(),
          child: Text(
            visibleScript,
            style: TextStyle(
              color: _warmCream.withValues(alpha: 242),
              fontSize: 19,
              height: 1.75,
              fontFamily: 'Pyeongtaek',
              fontWeight: FontWeight.w400,
              letterSpacing: 0.4,
              shadows: [
                Shadow(
                  color: _deepNavy.withValues(alpha: 128),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ★ 오디오 파형 애니메이션 위젯
class _AudioWaveform extends StatefulWidget {
  final bool isPlaying;
  final Color color;

  const _AudioWaveform({required this.isPlaying, required this.color});

  @override
  State<_AudioWaveform> createState() => _AudioWaveformState();
}

class _AudioWaveformState extends State<_AudioWaveform>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    if (widget.isPlaying) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(_AudioWaveform oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.isPlaying && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          size: const Size(32, 16),
          painter: _WaveformPainter(
            progress: _controller.value,
            isPlaying: widget.isPlaying,
            color: widget.color,
          ),
        );
      },
    );
  }
}

// ★ 파형 그리기 Painter
class _WaveformPainter extends CustomPainter {
  final double progress;
  final bool isPlaying;
  final Color color;

  _WaveformPainter({
    required this.progress,
    required this.isPlaying,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    const barCount = 7;
    const barWidth = 2.0;
    final spacing = (size.width - barCount * barWidth) / (barCount - 1);
    final centerY = size.height / 2;

    // 각 바의 기본 높이 패턴 (파형처럼 보이게)
    const baseHeights = [0.3, 0.5, 0.8, 1.0, 0.7, 0.4, 0.25];

    for (int i = 0; i < barCount; i++) {
      final x = i * (barWidth + spacing) + barWidth / 2;

      double heightRatio;
      if (isPlaying) {
        // 재생 중: 각 바가 다른 위상으로 움직임
        final phase = (progress * 2 * math.pi) + (i * 0.8);
        final wave = (0.5 + 0.5 * math.sin(phase));
        heightRatio = 0.2 + baseHeights[i] * wave * 0.8;
      } else {
        // 정지: 낮은 높이로 고정
        heightRatio = 0.15 + baseHeights[i] * 0.15;
      }

      final barHeight = size.height * heightRatio;
      final top = centerY - barHeight / 2;
      final bottom = centerY + barHeight / 2;

      canvas.drawLine(Offset(x, top), Offset(x, bottom), paint);
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.isPlaying != isPlaying;
  }
}
