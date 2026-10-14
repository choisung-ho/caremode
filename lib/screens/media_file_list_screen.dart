// lib/screens/media_file_list_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:caremode/services/storage_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:saf_util/saf_util.dart';
import 'package:saf_stream/saf_stream.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_compress/video_compress.dart';

/// 미디어 타입 enum
enum MediaType { video, photo, audio }

/// 미디어 파일 모델
class MediaFile {
  final String uri;
  final String fileName;
  final DateTime modifiedDate;
  final int size;
  bool isUploading;
  double uploadProgress;
  bool isUploaded;
  String? error;

  MediaFile({
    required this.uri,
    required this.fileName,
    required this.modifiedDate,
    required this.size,
    this.isUploading = false,
    this.uploadProgress = 0,
    this.isUploaded = false,
    this.error,
  });

  String get formattedSize {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String get formattedDate {
    return '${modifiedDate.month}/${modifiedDate.day} ${modifiedDate.hour}:${modifiedDate.minute.toString().padLeft(2, '0')}';
  }
}

/// 미디어 파일 리스트 화면
class MediaFileListScreen extends StatefulWidget {
  final String userCode;
  final MediaType mediaType;

  const MediaFileListScreen({
    super.key,
    required this.userCode,
    required this.mediaType,
  });

  @override
  State<MediaFileListScreen> createState() => _MediaFileListScreenState();
}

class _MediaFileListScreenState extends State<MediaFileListScreen> {
  final SafUtil _safUtil = SafUtil();
  final SafStream _safStream = SafStream();
  final StorageService _storageService = StorageService();

  List<MediaFile> _files = [];
  Set<String> _uploadedFileNames = {};
  bool _isLoading = true;
  String? _selectedFolderUri;
  bool _hasPermission = false;

  // SharedPreferences 키
  String get _prefsFolderKey => 'saf_${widget.mediaType.name}_folder_uri';

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await _loadSavedFolder();
    await _loadUploadedFiles();
    if (_hasPermission && _selectedFolderUri != null) {
      await _loadFiles();
    } else {
      setState(() => _isLoading = false);
    }
  }

  /// 저장된 폴더 URI 로드
  Future<void> _loadSavedFolder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _selectedFolderUri = prefs.getString(_prefsFolderKey);

      if (_selectedFolderUri != null) {
        final hasPermission = await _safUtil.hasPersistedPermission(
          _selectedFolderUri!,
          checkRead: true,
        );
        _hasPermission = hasPermission;

        if (!hasPermission) {
          _selectedFolderUri = null;
          await prefs.remove(_prefsFolderKey);
        }
      }
    } catch (e) {
      debugPrint('폴더 로드 실패: $e');
    }
  }

  /// 이미 업로드된 파일 목록 로드 (Firestore에서)
  Future<void> _loadUploadedFiles() async {
    try {
      final collection = _getFirestoreCollection();
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userCode)
          .collection(collection)
          .get();

      _uploadedFileNames = snapshot.docs
          .map((doc) => doc.data()['fileName'] as String?)
          .whereType<String>()
          .toSet();

      debugPrint('📋 이미 업로드된 파일: ${_uploadedFileNames.length}개');
    } catch (e) {
      debugPrint('업로드 목록 로드 실패: $e');
    }
  }

  String _getFirestoreCollection() {
    switch (widget.mediaType) {
      case MediaType.video:
        return 'videos';
      case MediaType.photo:
        return 'photos';
      case MediaType.audio:
        return 'audios';
    }
  }

  String _getStoragePath() {
    switch (widget.mediaType) {
      case MediaType.video:
        return 'videos';
      case MediaType.photo:
        return 'images';
      case MediaType.audio:
        return 'calls';
    }
  }

  List<String> _getExtensions() {
    switch (widget.mediaType) {
      case MediaType.video:
        return ['.mp4'];
      case MediaType.photo:
        return ['.jpg', '.jpeg', '.png'];
      case MediaType.audio:
        return ['.m4a', '.mp3', '.wav', '.aac'];
    }
  }

  String _getTitle() {
    switch (widget.mediaType) {
      case MediaType.video:
        return '동영상';
      case MediaType.photo:
        return '사진';
      case MediaType.audio:
        return '음성';
    }
  }

  IconData _getIcon() {
    switch (widget.mediaType) {
      case MediaType.video:
        return Icons.videocam_rounded;
      case MediaType.photo:
        return Icons.photo_rounded;
      case MediaType.audio:
        return Icons.mic_rounded;
    }
  }

  Color _getColor() {
    switch (widget.mediaType) {
      case MediaType.video:
        return Colors.blue;
      case MediaType.photo:
        return Colors.green;
      case MediaType.audio:
        return Colors.orange;
    }
  }

  /// 폴더 선택 요청
  Future<void> _requestFolderSelection() async {
    try {
      final dir = await _safUtil.pickDirectory(
        persistablePermission: true,
        writePermission: false,
      );

      if (dir == null) return;

      final uri = dir.uri;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsFolderKey, uri);

      setState(() {
        _selectedFolderUri = uri;
        _hasPermission = true;
        _isLoading = true;
      });

      await _loadFiles();
    } catch (e) {
      debugPrint('폴더 선택 실패: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('폴더 선택 실패: $e')));
      }
    }
  }

  /// 파일 목록 로드
  Future<void> _loadFiles() async {
    if (_selectedFolderUri == null) return;

    setState(() => _isLoading = true);

    try {
      final children = await _safUtil.list(_selectedFolderUri!);
      final extensions = _getExtensions();

      final files = children
          .where((child) {
            if (child.isDir) return false;
            final name = child.name.toLowerCase();
            return extensions.any((ext) => name.endsWith(ext));
          })
          .map(
            (child) => MediaFile(
              uri: child.uri,
              fileName: child.name,
              modifiedDate: DateTime.fromMillisecondsSinceEpoch(
                child.lastModified,
              ),
              size: child.length,
              isUploaded: _uploadedFileNames.contains(child.name),
            ),
          )
          .toList();

      // 날짜순 정렬 (최신순)
      files.sort((a, b) => b.modifiedDate.compareTo(a.modifiedDate));

      setState(() {
        _files = files;
        _isLoading = false;
      });

      debugPrint('📂 ${_getTitle()} 파일: ${files.length}개 로드됨');
    } catch (e) {
      debugPrint('파일 로드 실패: $e');
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('파일 로드 실패: $e')));
      }
    }
  }

  /// 파일 업로드
  Future<void> _uploadFile(MediaFile file) async {
    if (file.isUploaded) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('이미 업로드된 파일입니다'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final index = _files.indexOf(file);
    if (index == -1) return;

    setState(() {
      _files[index].isUploading = true;
      _files[index].uploadProgress = 0;
      _files[index].error = null;
    });

    try {
      // 1. SAF에서 임시 파일로 복사
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/${file.fileName}');

      debugPrint("📥 파일 복사 중");
      await _safStream.copyToLocalFile(file.uri, tempFile.path);

      File fileToUpload = tempFile;

      // 2. 동영상이고 50MB 초과시 압축
      if (widget.mediaType == MediaType.video && file.size > 50 * 1024 * 1024) {
        debugPrint('🗜️ 동영상 압축 시작 (${file.formattedSize})');

        final mediaInfo = await VideoCompress.compressVideo(
          tempFile.path,
          quality: VideoQuality.MediumQuality,
          deleteOrigin: false,
        );

        if (mediaInfo?.file != null) {
          fileToUpload = mediaInfo!.file!;
          final compressedSize = (await fileToUpload.length() / (1024 * 1024))
              .toStringAsFixed(1);
          debugPrint('✅ 압축 완료: ${file.formattedSize} → ${compressedSize}MB');
        }
      }

      // 3. Firebase Storage 업로드 (user_XXX/source/{folder}/{fileName})
      final storageRef = await _storageService.createRef(
        _getStoragePath(),
        file.fileName,
      );

      final uploadTask = storageRef.putFile(fileToUpload);

      uploadTask.snapshotEvents.listen((snapshot) {
        final progress =
            (snapshot.bytesTransferred / snapshot.totalBytes) * 100;
        if (mounted) {
          setState(() {
            _files[index].uploadProgress = progress;
          });
        }
      });

      await uploadTask;

      // 4. 다운로드 URL 가져오기
      final downloadUrl = await storageRef.getDownloadURL();

      // 5. Firestore에 메타데이터 저장
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userCode)
          .collection(_getFirestoreCollection())
          .add({
            'fileName': file.fileName,
            'downloadUrl': downloadUrl,
            'uploadedAt': FieldValue.serverTimestamp(),
            'fileSize': file.size,
            'originalDate': Timestamp.fromDate(file.modifiedDate),
          });

      // 6. 임시 파일 정리
      if (tempFile.existsSync()) await tempFile.delete();
      if (fileToUpload.path != tempFile.path && fileToUpload.existsSync()) {
        await fileToUpload.delete();
      }
      // 동영상일 때만 VideoCompress 캐시 삭제
      if (widget.mediaType == MediaType.video) {
        await VideoCompress.deleteAllCache();
      }

      // 7. 상태 업데이트
      _uploadedFileNames.add(file.fileName);

      if (mounted) {
        setState(() {
          _files[index].isUploading = false;
          _files[index].isUploaded = true;
          _files[index].uploadProgress = 100;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ ${file.fileName} 업로드 완료'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ 업로드 실패: $e');
      if (mounted) {
        setState(() {
          _files[index].isUploading = false;
          _files[index].error = e.toString();
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('업로드 실패: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = _getColor();

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        title: Row(
          children: [
            Icon(_getIcon(), color: color, size: 24),
            const SizedBox(width: 8),
            Text(
              _getTitle(),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontFamily: 'Pyeongtaek',
              ),
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_hasPermission)
            IconButton(
              icon: const Icon(Icons.folder_open),
              tooltip: '폴더 변경',
              onPressed: _requestFolderSelection,
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '새로고침',
            onPressed: () {
              _loadUploadedFiles().then((_) => _loadFiles());
            },
          ),
        ],
      ),
      body: _buildBody(scheme, isDark, color),
    );
  }

  Widget _buildBody(ColorScheme scheme, bool isDark, Color color) {
    // 폴더 미선택 상태
    if (!_hasPermission || _selectedFolderUri == null) {
      return _buildFolderSelectionView(scheme, isDark, color);
    }

    // 로딩 중
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: color),
            const SizedBox(height: 16),
            Text(
              '파일 로드 중...',
              style: TextStyle(color: scheme.onSurface.withOpacity(0.6)),
            ),
          ],
        ),
      );
    }

    // 파일 없음
    if (_files.isEmpty) {
      return _buildEmptyView(scheme, color);
    }

    // 파일 리스트
    return _buildFileList(scheme, isDark, color);
  }

  Widget _buildFolderSelectionView(
    ColorScheme scheme,
    bool isDark,
    Color color,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.folder_open, size: 50, color: color),
            ),
            const SizedBox(height: 24),
            Text(
              '${_getTitle()} 폴더를 선택해주세요',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: scheme.onSurface,
                fontFamily: 'Pyeongtaek',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '선택한 폴더에서 파일을 불러옵니다',
              style: TextStyle(
                fontSize: 14,
                color: scheme.onSurface.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _requestFolderSelection,
              icon: const Icon(Icons.folder_open),
              label: const Text('폴더 선택'),
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyView(ColorScheme scheme, Color color) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(_getIcon(), size: 64, color: scheme.onSurface.withOpacity(0.3)),
          const SizedBox(height: 16),
          Text(
            '${_getTitle()} 파일이 없습니다',
            style: TextStyle(
              fontSize: 16,
              color: scheme.onSurface.withOpacity(0.6),
            ),
          ),
          const SizedBox(height: 24),
          TextButton.icon(
            onPressed: _requestFolderSelection,
            icon: const Icon(Icons.folder_open),
            label: const Text('다른 폴더 선택'),
          ),
        ],
      ),
    );
  }

  Widget _buildFileList(ColorScheme scheme, bool isDark, Color color) {
    final uploadedCount = _files.where((f) => f.isUploaded).length;
    final pendingCount = _files.length - uploadedCount;

    return Column(
      children: [
        // 상태 바
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: isDark
                ? scheme.surfaceContainerHighest
                : scheme.surfaceContainerLow,
          ),
          child: Row(
            children: [
              Icon(
                Icons.folder,
                size: 18,
                color: scheme.onSurface.withOpacity(0.5),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '총 ${_files.length}개',
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.onSurface.withOpacity(0.7),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '업로드 완료: $uploadedCount',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.green,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '대기: $pendingCount',
                  style: TextStyle(
                    fontSize: 12,
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),

        // 파일 리스트
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: _files.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final file = _files[index];
              return _buildFileItem(file, scheme, isDark, color);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFileItem(
    MediaFile file,
    ColorScheme scheme,
    bool isDark,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? scheme.surfaceContainerHighest : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: file.isUploaded
            ? Border.all(color: Colors.green.withOpacity(0.5), width: 1.5)
            : Border.all(color: scheme.outline.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              // 파일 아이콘
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: file.isUploaded
                      ? Colors.green.withOpacity(0.15)
                      : color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  file.isUploaded ? Icons.cloud_done : _getIcon(),
                  color: file.isUploaded ? Colors.green : color,
                ),
              ),
              const SizedBox(width: 12),

              // 파일 정보
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.fileName,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          file.formattedSize,
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurface.withOpacity(0.5),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '•',
                          style: TextStyle(
                            color: scheme.onSurface.withOpacity(0.3),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          file.formattedDate,
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurface.withOpacity(0.5),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // 업로드 버튼
              if (file.isUploading)
                SizedBox(
                  width: 48,
                  height: 48,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: file.uploadProgress / 100,
                        strokeWidth: 3,
                        color: color,
                      ),
                      Text(
                        '${file.uploadProgress.toInt()}',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                )
              else if (file.isUploaded)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check, size: 16, color: Colors.green),
                      SizedBox(width: 4),
                      Text(
                        '완료',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.green,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                )
              else
                ElevatedButton(
                  onPressed: () => _uploadFile(file),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: color,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    '업로드',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),

          // 에러 메시지
          if (file.error != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                file.error!,
                style: const TextStyle(fontSize: 11, color: Colors.red),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
