import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_storage/shared_storage.dart';

/// 백엔드 팀 SAF(Storage Access Framework) 권한 영속화 가이드 적용용 서비스
///
/// 핵심 포인트
/// - 폴더 선택: `openDocumentTree(grantWritePermission: true)`
/// - 권한 검증: `persistedUriPermissions()`
/// - SAF URI는 `dart:io File`로 직접 접근하지 말고, DocumentFile API로 bytes를 읽어야 함
class SafService {
  static const String prefsKeyCallRecordFolderUri = 'call_record_folder_uri';

  // 레거시 키(기존 프로젝트에서 사용하던 SAF 폴더 키)
  static const String _legacyPrefsKeySafRecordingFolderUri =
      'saf_recording_folder_uri';

  // 로그인 기능이 없으므로 하드코딩
  static const String _testUserId = 'test_care_recipient_001';

  final FirebaseFirestore _firestore;

  SafService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  /// 폴더 선택 및 영속화
  /// - openDocumentTree(grantWritePermission: true)
  /// - 선택 URI를 SharedPreferences에 저장
  /// - Firestore에 권한 획득 여부 기록(userId 하드코딩)
  Future<Uri?> pickAndPersistCallFolder() async {
    final Uri? treeUri = await openDocumentTree(grantWritePermission: true);
    if (treeUri == null) return null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsKeyCallRecordFolderUri, treeUri.toString());

    try {
      await _firestore.collection('users').doc(_testUserId).set({
        'saf': {
          'callRecordFolder': {
            'granted': true,
            'uri': treeUri.toString(),
            'updatedAt': FieldValue.serverTimestamp(),
          },
        },
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('❌ Firestore SAF 권한 상태 저장 실패: $e');
    }

    return treeUri;
  }

  /// 저장된 URI를 가져오고, 실제 영속 권한이 유효한지 검증
  ///
  /// 반환:
  /// - 유효하면 Uri 반환
  /// - 무효하면 저장값 삭제 후 null
  Future<Uri?> getPersistedUri() async {
    final prefs = await SharedPreferences.getInstance();

    // 1) 우선 새 키를 시도
    final String? saved = prefs.getString(prefsKeyCallRecordFolderUri);
    final Uri? savedUri = saved == null ? null : Uri.tryParse(saved);

    // 2) 새 키가 없으면 레거시 키를 시도(마이그레이션)
    final String? legacy = prefs.getString(
      _legacyPrefsKeySafRecordingFolderUri,
    );
    final Uri? legacyUri = legacy == null ? null : Uri.tryParse(legacy);

    final Uri? candidate = savedUri ?? legacyUri;
    if (candidate == null) return null;

    final perms = await persistedUriPermissions();
    final bool isValid =
        perms?.any((p) => p.uri == candidate && p.isReadPermission) ?? false;

    if (!isValid) {
      // 저장값 정리
      await prefs.remove(prefsKeyCallRecordFolderUri);
      await prefs.remove(_legacyPrefsKeySafRecordingFolderUri);
      return null;
    }

    // 레거시만 있던 경우 새 키로 승격
    if (savedUri == null && legacyUri != null) {
      await prefs.setString(prefsKeyCallRecordFolderUri, legacyUri.toString());
    }

    return candidate;
  }

  /// SAF 폴더 내 파일 목록 조회 예시
  ///
  /// 중요:
  /// - SAF URI는 `dart:io File`로 직접 접근 불가
  /// - `listFiles()` + `DocumentFile`로 메타데이터/컨텐츠 접근
  Future<List<SafListedFile>> listFilesInFolder(Uri treeUri) async {
    final files = <SafListedFile>[];

    final onFile = listFiles(
      treeUri,
      columns: const [
        DocumentFileColumn.displayName,
        DocumentFileColumn.mimeType,
        DocumentFileColumn.size,
        DocumentFileColumn.lastModified,
        DocumentFileColumn.id,
      ],
    );

    await for (final f in onFile) {
      if (f.isFile != true) continue;
      files.add(
        SafListedFile(
          name: f.name ?? '(unknown)',
          uri: f.uri,
          mimeType: f.type,
          size: f.size,
          lastModified: f.lastModified,
        ),
      );
    }

    return files;
  }

  /// SAF 파일 바이트 읽기 예시
  ///
  /// - 대용량 파일은 한 번에 메모리에 올리면 부담될 수 있음
  /// - 하지만 "File로 직접 접근하지 말라"는 주의사항을 만족하기 위한 bytes 접근 예시를 제공
  Future<Uint8List> readFileBytes(Uri documentUri) async {
    final doc = await documentUri.toDocumentFile();
    if (doc == null) {
      throw StateError('DocumentFile.fromTreeUri() failed for $documentUri');
    }

    final bytes = await doc.getContent();
    if (bytes == null) {
      throw StateError('getContent() returned null for $documentUri');
    }

    return bytes;
  }
}

class SafListedFile {
  final String name;
  final Uri uri;
  final String? mimeType;
  final int? size;
  final DateTime? lastModified;

  const SafListedFile({
    required this.name,
    required this.uri,
    this.mimeType,
    this.size,
    this.lastModified,
  });
}
