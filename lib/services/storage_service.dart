import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 업로드 결과 (경로 + 다운로드 URL)
class StorageUploadResult {
  StorageUploadResult({required this.path, required this.downloadUrl});

  final String path;
  final String downloadUrl;
}

/// 로그인 없는 환경용 Firebase Storage 업로더.
/// 최초 1회 생성한 `user_XXX`를 SharedPreferences에 저장해 동일 기기에서 재사용한다.
class StorageService {
  StorageService() : _storage = FirebaseStorage.instance;

  final FirebaseStorage _storage;
  static const _prefsKey = 'storage_service_user_id';
  static const _prefsInitializedUserKey = 'storage_service_initialized_user_id';
  static String? _cachedUserId;

  static const List<String> _sourceFolders = <String>[
    'images',
    'videos',
    'calls',
    'sms_logs',
  ];

  /// 파일 업로드 (필요 시 파일명을 덮어씌울 수 있음)
  /// - 기본 파일명: [PREFIX]_yyyyMMdd_HHmmss + 원본 확장자
  /// - 경로: gs://dailyendproj.firebasestorage.app/{userId}/source/{folderName}/파일명
  Future<StorageUploadResult> uploadFile(
    File file,
    String folderName, {
    String? fileName,
  }) async {
    final targetFileName =
        fileName ?? _buildGeneratedName(folderName, file.path);
    final ref = await _buildRef(folderName, targetFileName);

    await ref.putFile(file);
    final url = await ref.getDownloadURL();
    return StorageUploadResult(path: ref.fullPath, downloadUrl: url);
  }

  /// 바이트 배열 업로드 (녹음 등)
  Future<StorageUploadResult> uploadBytes(
    Uint8List data,
    String folderName, {
    required String fileName,
    SettableMetadata? metadata,
  }) async {
    final ref = await _buildRef(folderName, fileName);
    await ref.putData(data, metadata);
    final url = await ref.getDownloadURL();
    return StorageUploadResult(path: ref.fullPath, downloadUrl: url);
  }

  /// 문자열 업로드 (JSON 등)
  Future<StorageUploadResult> uploadString(
    String content,
    String folderName, {
    required String fileName,
    String contentType = 'text/plain',
  }) async {
    final data = Uint8List.fromList(content.codeUnits);
    final metadata = SettableMetadata(contentType: contentType);
    return uploadBytes(
      data,
      folderName,
      fileName: fileName,
      metadata: metadata,
    );
  }

  /// 현재 기기의 userId 반환 (저장된 값 재사용)
  Future<String> getUserId() async {
    if (_cachedUserId != null) return _cachedUserId!;
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_prefsKey);
    if (existing != null && existing.isNotEmpty) {
      _cachedUserId = existing;
      await _ensureSourceInitialized(prefs, existing);
      return existing;
    }
    final generated = _generateUserId();
    await prefs.setString(_prefsKey, generated);
    _cachedUserId = generated;
    await _ensureSourceInitialized(prefs, generated);
    return generated;
  }

  /// user_XXX 생성/복구 시 source 하위 폴더가 항상 보이도록 placeholder 파일을 만든다.
  /// (Firebase Storage는 "폴더" 개념이 없어서, 오브젝트가 1개라도 있어야 콘솔에 폴더가 보임)
  Future<void> ensureSourceFolders() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = await getUserId();
    await _ensureSourceInitialized(prefs, userId, force: true);
  }

  Future<void> _ensureSourceInitialized(
    SharedPreferences prefs,
    String userId, {
    bool force = false,
  }) async {
    final initializedFor = prefs.getString(_prefsInitializedUserKey);
    if (!force && initializedFor == userId) {
      return;
    }

    // 1바이트 placeholder를 업로드해서 콘솔에 폴더가 보이게 한다.
    final bytes = Uint8List.fromList([0]);
    for (final folder in _sourceFolders) {
      final ref = _storage.ref().child('Users/$userId/source/$folder/.keep');
      try {
        await ref.putData(
          bytes,
          SettableMetadata(contentType: 'application/octet-stream'),
        );
      } catch (_) {
        // 이미 존재하거나 네트워크 순간 오류일 수 있음. 다음 폴더는 계속 시도.
      }
    }

    await prefs.setString(_prefsInitializedUserKey, userId);
  }

  Future<Reference> _buildRef(String folderName, String fileName) async {
    final userId = await getUserId();
    final path = 'Users/$userId/source/$folderName/$fileName';
    return _storage.ref().child(path);
  }

  /// 외부에서 경로만 필요할 때 사용 (예: 진행률 리스닝)
  Future<Reference> createRef(String folderName, String fileName) async {
    return _buildRef(folderName, fileName);
  }

  String _buildGeneratedName(String folderName, String filePath) {
    final now = DateTime.now();
    final ts = _formatTimestamp(now);
    final prefix = _prefixForFolder(folderName);
    final ext = _extensionFromPath(filePath);
    final safeExt = ext.isEmpty ? 'bin' : ext;
    return '${prefix}_$ts.$safeExt';
  }

  String _extensionFromPath(String filePath) {
    final normalized = filePath.replaceAll('\\', '/');
    final lastSlash = normalized.lastIndexOf('/');
    final baseName = lastSlash == -1
        ? normalized
        : normalized.substring(lastSlash + 1);
    final lastDot = baseName.lastIndexOf('.');
    if (lastDot <= 0 || lastDot >= baseName.length - 1) return '';
    return baseName.substring(lastDot + 1);
  }

  static String _generateUserId() {
    final n = Random().nextInt(999) + 1; // 001~999
    return 'user_${n.toString().padLeft(3, '0')}';
  }

  String _formatTimestamp(DateTime dt) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${dt.year}${two(dt.month)}${two(dt.day)}_${two(dt.hour)}${two(dt.minute)}${two(dt.second)}';
  }

  String _prefixForFolder(String folderName) {
    final lower = folderName.toLowerCase();
    if (lower.contains('image') || lower.contains('photo')) return 'IMG';
    if (lower.contains('video')) return 'VID';
    if (lower.contains('call')) return 'REC';
    if (lower.contains('sms') || lower.contains('message')) return 'SMS';
    return 'FILE';
  }
}
