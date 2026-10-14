// lib/services/video_upload_service.dart
import 'dart:async';
import 'dart:io';
// import 'dart:typed_data'; // 미사용 import 제거
import 'package:flutter/foundation.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:saf_util/saf_util.dart';
import 'package:saf_util/saf_util_platform_interface.dart';
import 'package:saf_stream/saf_stream.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_compress/video_compress.dart';

/// 동영상 파일 정보 모델 (SAF용)
class VideoFile {
  final String uri; // SAF URI
  final String fileName;
  final DateTime modifiedDate;
  final int size;

  VideoFile({
    required this.uri,
    required this.fileName,
    required this.modifiedDate,
    required this.size,
  });

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
    if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// 동영상 길이 추정 (대략적 - 실제로는 메타데이터 필요)
  String get estimatedDuration {
    // 대략 1MB당 10초로 추정 (평균 비트레이트 기준)
    final seconds = (size / (1024 * 1024)) * 10;
    if (seconds < 60) return '${seconds.toInt()}초';
    final minutes = seconds ~/ 60;
    final remainingSeconds = (seconds % 60).toInt();
    return '$minutes분 $remainingSeconds초';
  }
}

/// SAF 기반 동영상 자동 업로드 서비스
/// ✅ Google Play Store 정책 준수
/// ✅ 사용자가 직접 폴더 선택 → 영구 권한 획득
/// ✅ 하루동안 찍은 동영상 자동 감지 및 업로드
class VideoUploadService {
  static final VideoUploadService _instance = VideoUploadService._internal();
  factory VideoUploadService() => _instance;
  VideoUploadService._internal();

  static const String _prefsVideoFolderKey = 'saf_video_folder_uri';
  static const String _prefsSeniorCodeKey = 'caremode_senior_code';
  // 백엔드 문서 기준: 업로드 히스토리 키는 uploaded_history
  static const String _prefsUploadedHistoryKey = 'uploaded_history';
  // 레거시 키(이전 구현) 마이그레이션용
  static const String _prefsUploadedHistoryLegacyKey = 'video_uploaded_history';
  static const int _uploadedHistoryMaxItems = 1000;
  // static const String _prefsLastScanDateKey = 'video_last_scan_date'; // 미사용 필드 제거

  final SafUtil _safUtil = SafUtil();
  final SafStream _safStream = SafStream();

  String? _userCode;
  String? _selectedFolderUri;
  // DateTime? _serviceStartTime; // 미사용 필드 제거
  final Set<String> _uploadedFiles = {};
  Timer? _periodicScanTimer;
  bool _isUploading = false;
  bool _isStarted = false;
  Duration _scanInterval = const Duration(seconds: 30);

  /// SAF 폴더 URI가 설정되었는지 확인
  bool get hasFolderPermission => _selectedFolderUri != null;

  /// 선택된 폴더 URI
  String? get selectedFolderUri => _selectedFolderUri;

  /// 업로드 진행 중 여부
  bool get isUploading => _isUploading;

  /// 업로드 진행 상황 콜백
  Function(String fileName, double progress)? onUploadProgress;
  Function(String fileName, bool success, String? error)? onUploadComplete;

  String _buildUploadHistoryKey(SafDocumentFile file) {
    final lastModified = file.lastModified;
    final length = file.length;
    return '${file.name}|$lastModified|$length';
  }

  /// 서비스 시작
  Future<void> start(
    String userCode, {
    Duration scanInterval = const Duration(seconds: 30),
  }) async {
    // 이미 같은 코드로 실행 중이면 중복 시작 방지
    if (_isStarted && _userCode == userCode) {
      return;
    }

    _isStarted = true;
    _userCode = userCode;
    _scanInterval = scanInterval;

    debugPrint('🎬 동영상 업로드 서비스 시작 (코드: $userCode)');

    // 저장된 폴더 URI 로드
    await _loadSavedFolderUri();

    // 업로드 히스토리 로드 (앱 재시작 후에도 중복 업로드 방지)
    await _loadUploadedHistoryFromPrefs();

    // 폴더가 없으면 스캔/타이머를 시작하지 않고 대기 (ANR 완화)
    if (_selectedFolderUri == null) {
      debugPrint('⚠️ 동영상 폴더 미선택 → 스캔/타이머 보류');
      return;
    }

    _startScanningWorkflow();
  }

  /// 스캔 타이머 + 즉시 스캔을 한번에 시작
  void _startScanningWorkflow() {
    // 주기적 스캔 시작 (기본 30초)
    _startPeriodicScan();

    // 서비스 시작 시 바로 한번 스캔
    Future.delayed(const Duration(seconds: 5), () {
      scanAndUploadTodayVideos();
    });
  }

  /// 저장된 SAF 폴더 URI 로드
  Future<void> _loadSavedFolderUri() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _selectedFolderUri = prefs.getString(_prefsVideoFolderKey);

      if (_selectedFolderUri != null) {
        // 권한이 여전히 유효한지 확인
        final hasPermission = await _safUtil.hasPersistedPermission(
          _selectedFolderUri!,
          checkRead: true,
        );

        if (hasPermission) {
          debugPrint('📁 저장된 동영상 폴더 URI 로드됨 (권한 유효)');
        } else {
          debugPrint('⚠️ 저장된 폴더 URI의 권한이 만료되었습니다.');
          _selectedFolderUri = null;
          await prefs.remove(_prefsVideoFolderKey);
        }
      } else {
        debugPrint('⚠️ 동영상 폴더가 선택되지 않았습니다. 사용자에게 폴더 선택 요청 필요.');
      }
    } catch (e) {
      debugPrint('❌ 폴더 URI 로드 실패: $e');
    }
  }

  /// SharedPreferences에서 설정 로드 (백그라운드 호출용)
  Future<void> _loadSettingsFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // userCode 로드
      if (_userCode == null) {
        _userCode = prefs.getString(_prefsSeniorCodeKey);
        debugPrint('📱 SharedPreferences에서 userCode 로드: $_userCode');
      }

      // folderUri 로드
      if (_selectedFolderUri == null) {
        _selectedFolderUri = prefs.getString(_prefsVideoFolderKey);
        debugPrint(
          '📁 SharedPreferences에서 video folderUri 로드: $_selectedFolderUri',
        );
      }
    } catch (e) {
      debugPrint('❌ 설정 로드 실패: $e');
    }
  }

  /// 사용자에게 동영상 폴더 선택 요청 (SAF)
  /// 반환: 성공 여부
  Future<bool> requestFolderSelection() async {
    try {
      debugPrint('📂 SAF 동영상 폴더 선택 요청...');

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
      await prefs.setString(_prefsVideoFolderKey, uri);

      debugPrint('✅ 동영상 폴더 선택됨: $uri');

      // 폴더가 확보되었으므로 스캔/타이머 시작
      _startScanningWorkflow();
      return true;
    } catch (e) {
      debugPrint('❌ 폴더 선택 에러: $e');
      return false;
    }
  }

  /// 주기적 스캔 시작
  void _startPeriodicScan() {
    _periodicScanTimer?.cancel();
    _periodicScanTimer = Timer.periodic(_scanInterval, (_) {
      debugPrint('⏰ 주기적 동영상 스캔 시작...');
      scanAndUploadTodayVideos();
    });
    debugPrint('✅ ${_scanInterval.inSeconds}초 주기 스캔 타이머 시작');
  }

  /// 오늘 찍은 동영상 스캔 및 업로드
  Future<void> scanAndUploadTodayVideos() async {
    if (_isUploading) {
      debugPrint('⚠️ 이미 업로드 진행 중...');
      return;
    }

    // userCode나 folderUri가 없으면 SharedPreferences에서 로드 시도
    if (_userCode == null || _selectedFolderUri == null) {
      await _loadSettingsFromPrefs();
    }

    if (_userCode == null || _selectedFolderUri == null) {
      debugPrint(
        '⚠️ 스캔 불가: userCode=$_userCode, folderUri=$_selectedFolderUri',
      );
      return;
    }

    _isUploading = true;
    debugPrint('🔍 SAF로 오늘 동영상 스캔 시작...');

    try {
      final files = await _safUtil.list(_selectedFolderUri!);
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final stableThreshold = now.subtract(const Duration(minutes: 1));
      int uploadCount = 0;
      for (final file in files) {
        if (file.isDir) continue;
        if (!_isVideoFile(file.name)) continue;
        // 생성 중(쓰기 중) 파일 회피: 0바이트 또는 최근 수정된 파일은 스킵
        if (file.length == 0) continue;
        final historyKey = _buildUploadHistoryKey(file);
        // 우선 정확한 키가 있으면 중복으로 판단
        if (_uploadedFiles.contains(historyKey)) {
          continue;
        }
        // 호환: 과거에는 파일명만 저장했으므로, 파일명만 매칭되면 키로 승격 저장
        if (_uploadedFiles.contains(file.name)) {
          await _promoteLegacyHistoryEntry(
            legacyFileName: file.name,
            historyKey: historyKey,
          );
          continue;
        }
        final modDate = DateTime.fromMillisecondsSinceEpoch(file.lastModified);
        if (modDate.isBefore(todayStart)) continue;
        if (modDate.isAfter(stableThreshold)) continue;
        debugPrint('🎬 오늘 찍은 동영상 발견: ${file.name}');
        await _uploadVideoFromSaf(file);
        uploadCount++;
      }
      debugPrint('✅ 동영상 스캔 완료: $uploadCount개 업로드됨');
    } catch (e) {
      debugPrint('❌ SAF 스캔 에러: $e');
    } finally {
      _isUploading = false;
    }
  }

  /// 특정 기간 동영상 스캔 및 업로드
  Future<int> scanAndUploadVideosInRange({
    required DateTime startDate,
    DateTime? endDate,
  }) async {
    if (_isUploading) {
      debugPrint('⚠️ 이미 업로드 진행 중...');
      return 0;
    }

    if (_userCode == null || _selectedFolderUri == null) {
      await _loadSettingsFromPrefs();
    }

    if (_userCode == null || _selectedFolderUri == null) {
      debugPrint('⚠️ 스캔 불가');
      return 0;
    }

    _isUploading = true;
    final end = endDate ?? DateTime.now();
    final stableThreshold = DateTime.now().subtract(const Duration(minutes: 1));

    debugPrint('🔍 동영상 스캔: $startDate ~ $end');

    int uploadCount = 0;

    try {
      final files = await _safUtil.list(_selectedFolderUri!);
      for (final file in files) {
        if (file.isDir) continue;
        if (!_isVideoFile(file.name)) continue;
        if (file.length == 0) continue;
        final historyKey = _buildUploadHistoryKey(file);
        // 우선 정확한 키가 있으면 중복으로 판단
        if (_uploadedFiles.contains(historyKey)) {
          continue;
        }
        // 호환: 과거에는 파일명만 저장했으므로, 파일명만 매칭되면 키로 승격 저장
        if (_uploadedFiles.contains(file.name)) {
          await _promoteLegacyHistoryEntry(
            legacyFileName: file.name,
            historyKey: historyKey,
          );
          continue;
        }
        final modDate = DateTime.fromMillisecondsSinceEpoch(file.lastModified);
        if (modDate.isBefore(startDate) || modDate.isAfter(end)) continue;
        if (modDate.isAfter(stableThreshold)) continue;
        debugPrint('🎬 기간 내 동영상 발견: ${file.name}');
        await _uploadVideoFromSaf(file);
        uploadCount++;
      }
    } catch (e) {
      debugPrint('❌ 스캔 에러: $e');
    } finally {
      _isUploading = false;
    }

    return uploadCount;
  }

  /// 동영상 파일인지 확인 (.mp4만 지원)
  bool _isVideoFile(String fileName) {
    final ext = fileName.toLowerCase();
    return ext.endsWith('.mp4');
  }

  /// SAF에서 파일 읽어서 Firebase Storage에 업로드
  /// ★ 대용량 파일은 압축 후 업로드
  Future<void> _uploadVideoFromSaf(SafDocumentFile file) async {
    if (_userCode == null) return;

    final historyKey = _buildUploadHistoryKey(file);
    _uploadedFiles.add(historyKey);
    File? tempFile;
    File? compressedFile;

    try {
      final fileSizeMB = file.length / (1024 * 1024);
      debugPrint(
        '📤 동영상 업로드 준비: ${file.name} (${fileSizeMB.toStringAsFixed(1)} MB)',
      );
      debugPrint('📤 임시 파일로 복사 중...');
      final tempDir = await getTemporaryDirectory();
      final tempPath =
          '${tempDir.path}/upload_${DateTime.now().millisecondsSinceEpoch}_${file.name}';
      tempFile = File(tempPath);
      final inputStream = await _safStream.readFileStream(file.uri);
      final outputSink = tempFile.openWrite();
      await for (final chunk in inputStream) {
        outputSink.add(chunk);
      }
      await outputSink.close();
      File fileToUpload = tempFile;
      int finalFileSize = file.length;
      if (fileSizeMB > 50) {
        debugPrint('🗜️ 파일 크기 ${fileSizeMB.toStringAsFixed(1)}MB → 압축 시작...');
        try {
          final mediaInfo = await VideoCompress.compressVideo(
            tempFile.path,
            quality: VideoQuality.MediumQuality,
            deleteOrigin: false,
            includeAudio: true,
          );
          if (mediaInfo != null && mediaInfo.file != null) {
            compressedFile = mediaInfo.file!;
            fileToUpload = compressedFile;
            finalFileSize = await compressedFile.length();
            final compressedSizeMB = finalFileSize / (1024 * 1024);
            debugPrint(
              '✅ 압축 완료: ${fileSizeMB.toStringAsFixed(1)}MB → ${compressedSizeMB.toStringAsFixed(1)}MB',
            );
          } else {
            debugPrint('⚠️ 압축 실패, 원본으로 업로드 시도');
          }
        } catch (compressError) {
          debugPrint('⚠️ 압축 에러: $compressError, 원본으로 업로드 시도');
        }
      }
      debugPrint('📤 Firebase Storage 업로드 시작: ${file.name}');
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('videos')
          .child(_userCode!)
          .child('${DateTime.now().millisecondsSinceEpoch}_${file.name}');
      final uploadTask = storageRef.putFile(
        fileToUpload,
        SettableMetadata(
          contentType: 'video/mp4',
          customMetadata: {
            'userCode': _userCode!,
            'originalFileName': file.name,
            'uploadedAt': DateTime.now().toIso8601String(),
            'fileSize': finalFileSize.toString(),
            'originalSize': file.length.toString(),
            'compressed': (compressedFile != null).toString(),
          },
        ),
      );
      uploadTask.snapshotEvents.listen((snapshot) {
        final progress = snapshot.bytesTransferred / snapshot.totalBytes * 100;
        debugPrint('📤 동영상 업로드: ${progress.toStringAsFixed(0)}%');
        onUploadProgress?.call(file.name, progress);
      });
      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();
      debugPrint('✅ 동영상 업로드 완료: $downloadUrl');
      await _saveToFirestore(
        file.name,
        downloadUrl,
        file.length,
        file.lastModified,
      );

      // 성공한 파일만 히스토리에 기록
      await _markUploadedPersisted(historyKey);
      onUploadComplete?.call(file.name, true, null);
    } catch (e) {
      debugPrint('❌ 동영상 업로드 실패: $e');
      _uploadedFiles.remove(historyKey);
      onUploadComplete?.call(file.name, false, e.toString());
    } finally {
      if (tempFile != null && await tempFile.exists()) {
        await tempFile.delete();
        debugPrint('🗑️ 임시 파일 삭제됨');
      }
      if (compressedFile != null && await compressedFile.exists()) {
        await compressedFile.delete();
        debugPrint('🗑️ 압축 파일 삭제됨');
      }
      await VideoCompress.deleteAllCache();
    }
  }

  // Content-Type 결정 함수는 사용되지 않으므로 제거

  /// Firestore에 저장
  Future<void> _saveToFirestore(
    String fileName,
    String downloadUrl,
    int fileSize,
    int? lastModified,
  ) async {
    if (_userCode == null) return;

    final videoData = {
      'fileName': fileName,
      'downloadUrl': downloadUrl,
      'fileSize': fileSize,
      'recordedAt': lastModified != null
          ? DateTime.fromMillisecondsSinceEpoch(lastModified).toIso8601String()
          : DateTime.now().toIso8601String(),
      'uploadedAt': FieldValue.serverTimestamp(),
      'analyzed': false,
      'type': 'video',
    };

    // 1. 동영상 기록 컬렉션에 추가
    await FirebaseFirestore.instance
        .collection('users')
        .doc(_userCode)
        .collection('videos')
        .add(videoData);

    // 2. 최신 동영상 URL → 메인 문서 (백엔드 트리거용)
    await FirebaseFirestore.instance.collection('users').doc(_userCode).update({
      'latestVideo': {
        'url': downloadUrl,
        'fileName': fileName,
        'fileSize': fileSize,
        'timestamp': FieldValue.serverTimestamp(),
        'analyzed': false,
      },
    });

    debugPrint('💾 동영상 Firestore 저장 완료');
  }

  /// 동영상 폴더 찾기 (SAF에서는 선택된 URI 반환)
  Future<String?> findVideoFolder() async {
    return _selectedFolderUri;
  }

  /// 권한 체크 (SAF에서는 폴더 선택 여부 확인)
  Future<bool> checkAndRequestStoragePermission() async {
    return _selectedFolderUri != null;
  }

  /// 기존 동영상 파일 목록 (SAF 방식)
  Future<List<VideoFile>> getExistingVideos({bool todayOnly = false}) async {
    final List<VideoFile> videos = [];

    if (_selectedFolderUri == null) {
      debugPrint('⚠️ 동영상 폴더가 선택되지 않았습니다.');
      return videos;
    }

    debugPrint('🔍 SAF로 동영상 파일 스캔...');

    try {
      final files = await _safUtil.list(_selectedFolderUri!);
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);

      for (final file in files) {
        if (file.isDir) continue;
        if (!_isVideoFile(file.name)) continue;

        final modDate = DateTime.fromMillisecondsSinceEpoch(file.lastModified);

        // 오늘만 필터링
        if (todayOnly && modDate.isBefore(todayStart)) {
          continue;
        }

        videos.add(
          VideoFile(
            uri: file.uri,
            fileName: file.name,
            modifiedDate: modDate,
            size: file.length,
          ),
        );
      }

      // 최신순 정렬
      videos.sort((a, b) => b.modifiedDate.compareTo(a.modifiedDate));

      debugPrint('📊 총 ${videos.length}개 동영상 파일 발견');
    } catch (e) {
      debugPrint('❌ SAF 스캔 에러: $e');
    }

    return videos;
  }

  /// 오늘 업로드된 동영상 개수 조회
  Future<int> getTodayUploadedCount() async {
    if (_userCode == null) {
      await _loadSettingsFromPrefs();
    }

    if (_userCode == null) return 0;

    try {
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);

      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(_userCode)
          .collection('videos')
          .where(
            'uploadedAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart),
          )
          .get();

      return snapshot.docs.length;
    } catch (e) {
      debugPrint('❌ 업로드 개수 조회 실패: $e');
      return 0;
    }
  }

  /// 수동 업로드 트리거
  Future<void> triggerManualUpload() async {
    debugPrint('🔄 수동 동영상 업로드 트리거');
    await scanAndUploadTodayVideos();
  }

  /// 서비스 중지
  void stop() {
    _periodicScanTimer?.cancel();
    _periodicScanTimer = null;
    _isStarted = false;
    debugPrint('🎬 동영상 업로드 서비스 중지');
  }

  /// 폴더 선택 해제 (설정 초기화)
  Future<void> clearFolderSelection() async {
    _selectedFolderUri = null;
    _uploadedFiles.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsVideoFolderKey);
    await prefs.remove(_prefsUploadedHistoryKey);
    await prefs.remove(_prefsUploadedHistoryLegacyKey);
    debugPrint('🗑️ 동영상 폴더 선택 해제됨');
  }

  Future<void> _loadUploadedHistoryFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final current =
          prefs.getStringList(_prefsUploadedHistoryKey) ?? const <String>[];
      final legacy =
          prefs.getStringList(_prefsUploadedHistoryLegacyKey) ??
          const <String>[];

      final merged = <String>{...current, ...legacy}.toList();
      _uploadedFiles
        ..clear()
        ..addAll(merged);

      // 레거시가 있으면 새 키로 마이그레이션
      if (legacy.isNotEmpty) {
        await prefs.setStringList(_prefsUploadedHistoryKey, merged);
        await prefs.remove(_prefsUploadedHistoryLegacyKey);
      }

      debugPrint('📋 업로드 히스토리 로드: ${merged.length}개');
    } catch (e) {
      debugPrint('❌ 업로드 히스토리 로드 실패: $e');
    }
  }

  Future<void> _promoteLegacyHistoryEntry({
    required String legacyFileName,
    required String historyKey,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final current =
          prefs.getStringList(_prefsUploadedHistoryKey) ?? <String>[];

      var changed = false;
      if (!current.contains(historyKey)) {
        current.add(historyKey);
        changed = true;
      }

      while (current.remove(legacyFileName)) {
        changed = true;
      }

      if (!changed) {
        // in-memory는 안전하게 정리
        _uploadedFiles
          ..add(historyKey)
          ..remove(legacyFileName);
        return;
      }

      // 너무 커지지 않도록 최근 N개만 유지
      final List<String> normalized;
      if (current.length > _uploadedHistoryMaxItems) {
        final start = current.length - _uploadedHistoryMaxItems;
        normalized = current.sublist(start);
      } else {
        normalized = current;
      }

      await prefs.setStringList(_prefsUploadedHistoryKey, normalized);

      _uploadedFiles
        ..add(historyKey)
        ..remove(legacyFileName);
    } catch (e) {
      debugPrint('❌ 업로드 히스토리 승격 실패: $e');
    }
  }

  Future<void> _markUploadedPersisted(String historyKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final current =
          prefs.getStringList(_prefsUploadedHistoryKey) ?? <String>[];
      if (!current.contains(historyKey)) {
        current.add(historyKey);
      }

      // 너무 커지지 않도록 최근 N개만 유지
      if (current.length > _uploadedHistoryMaxItems) {
        final start = current.length - _uploadedHistoryMaxItems;
        final trimmed = current.sublist(start);
        await prefs.setStringList(_prefsUploadedHistoryKey, trimmed);
      } else {
        await prefs.setStringList(_prefsUploadedHistoryKey, current);
      }
    } catch (e) {
      debugPrint('❌ 업로드 히스토리 저장 실패: $e');
    }
  }
}

/// 전역 인스턴스
final videoUploadService = VideoUploadService();
