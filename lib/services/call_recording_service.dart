// lib/services/call_recording_service.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:caremode/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:saf_util/saf_util.dart';
import 'package:saf_util/saf_util_platform_interface.dart';
import 'package:saf_stream/saf_stream.dart';
import 'package:flutter_phone_call_state/flutter_phone_call_state.dart';

/// 녹음 파일 정보 모델 (SAF용)
class RecordingFile {
  final String uri; // SAF URI
  final String fileName;
  final DateTime modifiedDate;
  final int size;

  RecordingFile({
    required this.uri,
    required this.fileName,
    required this.modifiedDate,
    required this.size,
  });

  /// 파일명에서 연락처 이름 추출 (예: "통화 녹음 차겸이형_251216_191519")
  String get contactName {
    final name = fileName.replaceAll('.m4a', '').replaceAll('.amr', '');
    // "통화 녹음 " 제거
    if (name.startsWith('통화 녹음 ')) {
      final parts = name.substring(5).split('_');
      if (parts.isNotEmpty) return parts[0];
    }
    return name;
  }

  /// 포맷된 날짜
  String get formattedDate {
    final now = DateTime.now();
    if (modifiedDate.day == now.day &&
        modifiedDate.month == now.month &&
        modifiedDate.year == now.year) {
      return '오늘 ${modifiedDate.hour}:${modifiedDate.minute.toString().padLeft(2, '0')}';
    }
    return '${modifiedDate.month}월 ${modifiedDate.day}일 ${modifiedDate.hour}:${modifiedDate.minute.toString().padLeft(2, '0')}';
  }

  /// 파일 크기 포맷
  String get formattedSize {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// SAF 기반 통화 녹음 파일 서비스
/// ✅ Google Play Store 정책 준수
/// ✅ 사용자가 직접 폴더 선택 → 영구 권한 획득
class CallRecordingService {
  static final CallRecordingService _instance =
      CallRecordingService._internal();
  factory CallRecordingService() => _instance;
  CallRecordingService._internal();

  // 레거시 키(기존 saf_util 기반 선택)
  static const String _prefsRecordingFolderKey = 'saf_recording_folder_uri';
  // 백엔드 가이드(shared_storage) 키
  static const String _prefsCallRecordFolderKey = 'call_record_folder_uri';

  final SafUtil _safUtil = SafUtil();
  final SafStream _safStream = SafStream();
  final StorageService _storageService = StorageService();

  String? _userCode;
  String? _selectedFolderUri;
  DateTime? _serviceStartTime;
  final Set<String> _uploadedFiles = {};
  bool _isInCall = false;
  StreamSubscription? _phoneStateSubscription;

  /// SAF 폴더 URI가 설정되었는지 확인
  bool get hasFolderPermission => _selectedFolderUri != null;

  /// 선택된 폴더 URI
  String? get selectedFolderUri => _selectedFolderUri;

  /// 서비스 시작
  Future<void> start(String userCode) async {
    _userCode = userCode;
    _serviceStartTime = DateTime.now();

    debugPrint('Call recording service started');

    // 저장된 폴더 URI 로드
    await _loadSavedFolderUri();

    // 통화 상태 감지 시작
    await _startPhoneStateListener();
  }

  /// 저장된 SAF 폴더 URI 로드
  Future<void> _loadSavedFolderUri() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // 우선 백엔드 가이드 키를 사용, 없으면 레거시 키로 폴백
      _selectedFolderUri =
          prefs.getString(_prefsCallRecordFolderKey) ??
          prefs.getString(_prefsRecordingFolderKey);

      if (_selectedFolderUri != null) {
        // 권한이 여전히 유효한지 확인
        final hasPermission = await _safUtil.hasPersistedPermission(
          _selectedFolderUri!,
          checkRead: true,
        );

        if (hasPermission) {
          debugPrint('📁 저장된 녹음 폴더 URI 로드됨 (권한 유효)');

          // 레거시만 저장돼 있던 경우 새 키로도 승격 저장
          if (!prefs.containsKey(_prefsCallRecordFolderKey)) {
            await prefs.setString(
              _prefsCallRecordFolderKey,
              _selectedFolderUri!,
            );
          }
        } else {
          debugPrint('⚠️ 저장된 폴더 URI의 권한이 만료되었습니다.');
          _selectedFolderUri = null;
          await prefs.remove(_prefsCallRecordFolderKey);
          await prefs.remove(_prefsRecordingFolderKey);
        }
      } else {
        debugPrint('⚠️ 녹음 폴더가 선택되지 않았습니다. 사용자에게 폴더 선택 요청 필요.');
      }
    } catch (e) {
      debugPrint('❌ 폴더 URI 로드 실패: $e');
    }
  }

  /// SharedPreferences에서 설정 로드 (백그라운드 호출용)
  static const String _prefsSeniorCodeKey = 'caremode_senior_code';

  Future<void> _loadSettingsFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // userCode 로드
      if (_userCode == null) {
        _userCode = prefs.getString(_prefsSeniorCodeKey);
        debugPrint('Call recording configuration loaded');
      }

      // folderUri 로드
      if (_selectedFolderUri == null) {
        _selectedFolderUri =
            prefs.getString(_prefsCallRecordFolderKey) ??
            prefs.getString(_prefsRecordingFolderKey);
        debugPrint("📁 SharedPreferences에서 folderUri 로드");
      }
    } catch (e) {
      debugPrint('❌ 설정 로드 실패: $e');
    }
  }

  /// 사용자에게 녹음 폴더 선택 요청 (SAF)
  /// 반환: 성공 여부
  Future<bool> requestFolderSelection() async {
    try {
      debugPrint('📂 SAF 폴더 선택 요청...');

      // SAF를 통해 폴더 선택 다이얼로그 표시 (영구 권한 요청)
      final dir = await _safUtil.pickDirectory(
        persistablePermission: true,
        writePermission: false, // 읽기만 필요
      );

      if (dir == null) {
        debugPrint('❌ 폴더 선택 취소됨');
        return false;
      }

      final uri = dir.uri;

      _selectedFolderUri = uri;

      // URI 영구 저장
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsRecordingFolderKey, uri);
      await prefs.setString(_prefsCallRecordFolderKey, uri);

      debugPrint("✅ 녹음 폴더 선택됨");
      return true;
    } catch (e) {
      debugPrint('❌ 폴더 선택 에러: $e');
      return false;
    }
  }

  /// 통화 상태 리스너 시작
  Future<void> _startPhoneStateListener() async {
    try {
      if (Platform.isAndroid) {
        PhoneCallState.instance.startMonitorService();
      }

      _phoneStateSubscription = PhoneCallState.instance.phoneStateChange.listen(
        _onPhoneStateChanged,
        onError: (e) => debugPrint('📞 통화 상태 에러: $e'),
      );

      debugPrint('✅ 통화 상태 리스너 시작됨');
    } catch (e) {
      debugPrint('❌ 통화 상태 리스너 시작 실패: $e');
      _startFallbackPolling();
    }
  }

  /// 통화 상태 변화 핸들러
  void _onPhoneStateChanged(CallResult event) {
    debugPrint("📞 통화 이벤트");

    switch (event.state) {
      case CallState.incoming:
      case CallState.outgoing:
        _isInCall = true;
        debugPrint('📞 통화 시작됨');
        break;

      case CallState.call:
      case CallState.outgoingAccept:
        _isInCall = true;
        debugPrint('📞 통화 중...');
        break;

      case CallState.end:
        if (_isInCall) {
          _isInCall = false;
          debugPrint('📞 통화 종료됨 - 녹음 파일 확인 중...');

          // 통화 종료 후 녹음 파일 스캔 및 업로드
          Future.delayed(const Duration(seconds: 3), () {
            scanAndUploadNewRecordings();
          });
        }
        break;

      case CallState.none:
      case CallState.hold:
      case CallState.interruptAndHold:
        break;
    }
  }

  /// 폴백: 폴링 방식
  Timer? _fallbackTimer;
  void _startFallbackPolling() {
    debugPrint('⚠️ 폴백 모드: 60초마다 폴링');
    _fallbackTimer?.cancel();
    _fallbackTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      scanAndUploadNewRecordings();
    });
  }

  /// 새 녹음 파일 스캔 및 업로드 (외부에서 호출 가능)
  Future<void> scanAndUploadNewRecordings() async {
    // userCode나 folderUri가 없으면 SharedPreferences에서 로드 시도
    if (_userCode == null || _selectedFolderUri == null) {
      await _loadSettingsFromPrefs();
    }

    if (_userCode == null || _selectedFolderUri == null) {
      debugPrint('Call recording configuration incomplete');
      return;
    }

    debugPrint('🔍 saf_util로 녹음 파일 스캔 시작...');

    try {
      final files = await _safUtil.list(_selectedFolderUri!);

      for (final file in files) {
        if (file.isDir) continue;
        if (!_isAudioFile(file.name)) continue;
        if (_uploadedFiles.contains(file.uri)) continue;

        // 서비스 시작 이후 파일만 (lastModified 체크)
        if (_serviceStartTime != null) {
          final modDate = DateTime.fromMillisecondsSinceEpoch(
            file.lastModified,
          );
          if (modDate.isBefore(_serviceStartTime!)) {
            continue;
          }
        }

        debugPrint("🎙️ 새 통화 녹음 발견(saf_util)");
        await _uploadRecordingFromSaf(file);
      }
    } catch (e) {
      debugPrint('❌ SAF 스캔 에러: $e');
    }
  }

  bool _isAudioFile(String fileName) {
    final ext = fileName.toLowerCase();
    return ext.endsWith('.m4a') ||
        ext.endsWith('.amr') ||
        ext.endsWith('.wav') ||
        ext.endsWith('.mp3') ||
        ext.endsWith('.aac') ||
        ext.endsWith('.3gp');
  }

  /// SAF에서 파일 읽어서 Firebase Storage에 업로드
  Future<void> _uploadRecordingFromSaf(SafDocumentFile file) async {
    if (_userCode == null) return;

    _uploadedFiles.add(file.uri);

    try {
      debugPrint("📤 SAF 파일 읽기 시작");

      // SAF URI에서 파일 데이터 읽기 (saf_stream 사용)
      final Uint8List fileData = await _readFileFromSaf(file.uri);

      debugPrint(
        '📤 Firebase Storage 업로드 시작: ${file.name} (${fileData.length} bytes)',
      );

      final ref = await _storageService.createRef(
        'calls',
        '${DateTime.now().millisecondsSinceEpoch}_${file.name}',
      );

      final uploadTask = ref.putData(
        fileData,
        SettableMetadata(
          contentType: _getContentType(file.name),
          customMetadata: {
            'userCode': _userCode!,
            'originalFileName': file.name,
            'uploadedAt': DateTime.now().toIso8601String(),
          },
        ),
      );

      uploadTask.snapshotEvents.listen((snapshot) {
        final progress = snapshot.bytesTransferred / snapshot.totalBytes * 100;
        debugPrint('📤 업로드: ${progress.toStringAsFixed(0)}%');
      });

      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();

      debugPrint("✅ 업로드 완료");

      // Firestore에 저장
      await _saveToFirestore(
        file.name,
        downloadUrl,
        fileData.length,
        file.lastModified,
      );
    } catch (e) {
      debugPrint('❌ 업로드 실패: $e');
      _uploadedFiles.remove(file.uri);
    }
  }

  /// SAF URI에서 파일 전체 읽기
  Future<Uint8List> _readFileFromSaf(String uri) async {
    return await _safStream.readFileBytes(uri);
  }

  String _getContentType(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.m4a')) return 'audio/mp4';
    if (lower.endsWith('.amr')) return 'audio/amr';
    if (lower.endsWith('.wav')) return 'audio/wav';
    if (lower.endsWith('.mp3')) return 'audio/mpeg';
    if (lower.endsWith('.aac')) return 'audio/aac';
    if (lower.endsWith('.3gp')) return 'audio/3gpp';
    return 'audio/mpeg';
  }

  /// Firestore에 저장
  Future<void> _saveToFirestore(
    String fileName,
    String downloadUrl,
    int fileSize,
    int? lastModified,
  ) async {
    if (_userCode == null) return;

    final recordingData = {
      'fileName': fileName,
      'downloadUrl': downloadUrl,
      'fileSize': fileSize,
      'recordedAt': lastModified != null
          ? DateTime.fromMillisecondsSinceEpoch(lastModified).toIso8601String()
          : DateTime.now().toIso8601String(),
      'uploadedAt': FieldValue.serverTimestamp(),
      'analyzed': false,
    };

    // 1. 녹음 기록 컬렉션에 추가
    await FirebaseFirestore.instance
        .collection('users')
        .doc(_userCode)
        .collection('call_recordings')
        .add(recordingData);

    // 2. 최신 녹음 URL → 메인 문서 (백엔드 트리거용)
    await FirebaseFirestore.instance.collection('users').doc(_userCode).update({
      'latestCallRecording': {
        'url': downloadUrl,
        'fileName': fileName,
        'timestamp': FieldValue.serverTimestamp(),
        'analyzed': false,
      },
    });

    debugPrint('💾 Firestore 저장 완료 → 백엔드 분석 대기');
  }

  /// 녹음 폴더 찾기 (SAF에서는 선택된 URI 반환)
  Future<String?> findRecordingFolder() async {
    return _selectedFolderUri;
  }

  /// 권한 체크 (SAF에서는 폴더 선택 여부 확인)
  Future<bool> checkAndRequestStoragePermission() async {
    return _selectedFolderUri != null;
  }

  /// 기존 녹음 파일 목록 (SAF 방식)
  Future<List<RecordingFile>> getExistingRecordings() async {
    final List<RecordingFile> recordings = [];

    if (_selectedFolderUri == null) {
      debugPrint('⚠️ 녹음 폴더가 선택되지 않았습니다.');
      return recordings;
    }

    debugPrint('🔍 SAF로 녹음 파일 스캔...');

    try {
      final files = await _safUtil.list(_selectedFolderUri!);

      for (final file in files) {
        if (file.isDir) continue;
        if (!_isAudioFile(file.name)) continue;

        recordings.add(
          RecordingFile(
            uri: file.uri,
            fileName: file.name,
            modifiedDate: DateTime.fromMillisecondsSinceEpoch(
              file.lastModified,
            ),
            size: file.length,
          ),
        );
      }

      // 최신순 정렬
      recordings.sort((a, b) => b.modifiedDate.compareTo(a.modifiedDate));

      debugPrint('📊 총 ${recordings.length}개 녹음 파일 발견');
    } catch (e) {
      debugPrint('❌ SAF 스캔 에러: $e');
    }

    return recordings;
  }

  /// SAF URI에서 파일 데이터 읽기 (재생용)
  Future<Uint8List?> readFileData(String uri) async {
    try {
      return await _readFileFromSaf(uri);
    } catch (e) {
      debugPrint('❌ 파일 읽기 에러: $e');
      return null;
    }
  }

  /// 서비스 중지
  void stop() {
    _phoneStateSubscription?.cancel();
    _phoneStateSubscription = null;
    _fallbackTimer?.cancel();
    _fallbackTimer = null;
    debugPrint('📞 통화 녹음 서비스 중지');
  }
}

/// 전역 인스턴스
final callRecordingService = CallRecordingService();
