import 'package:flutter/material.dart';

import '../services/saf_service.dart';

/// SAF(통화녹음 폴더) 권한 설정/검증 UI 예시 위젯
///
/// - "폴더 선택 & 영속화" 버튼
/// - "권한 유효성 검사" 버튼
/// - "파일 목록 예시" 버튼
class SafCallFolderSettingsSnippet extends StatefulWidget {
  const SafCallFolderSettingsSnippet({super.key});

  @override
  State<SafCallFolderSettingsSnippet> createState() =>
      _SafCallFolderSettingsSnippetState();
}

class _SafCallFolderSettingsSnippetState
    extends State<SafCallFolderSettingsSnippet> {
  final SafService _safService = SafService();

  bool _loading = false;
  Uri? _persistedUri;
  String _status = '권한 상태 확인 전';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _status = '권한 확인 중...';
    });

    try {
      final uri = await _safService.getPersistedUri();
      setState(() {
        _persistedUri = uri;
        _status = uri != null ? '권한 유효' : '권한 없음/만료';
      });
    } catch (e) {
      setState(() => _status = '오류: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _pick() async {
    setState(() {
      _loading = true;
      _status = '폴더 선택 중...';
    });

    try {
      final uri = await _safService.pickAndPersistCallFolder();
      setState(() {
        _persistedUri = uri;
        _status = uri != null ? '폴더 선택/저장 성공' : '사용자 취소/실패';
      });
    } catch (e) {
      setState(() => _status = '오류: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _listFiles() async {
    final uri = _persistedUri;
    if (uri == null) {
      setState(() => _status = '먼저 폴더를 선택하세요.');
      return;
    }

    setState(() {
      _loading = true;
      _status = '파일 목록 불러오는 중...';
    });

    try {
      final files = await _safService.listFilesInFolder(uri);
      final preview = files
          .take(5)
          .map((f) {
            final size = f.size ?? 0;
            return '- ${f.name} ($size bytes)';
          })
          .join('\n');

      setState(() {
        _status = '파일 ${files.length}개 발견\n$preview';
      });
    } catch (e) {
      setState(() => _status = '오류: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'SAF 통화녹음 폴더 권한',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text('상태: $_status'),
            const SizedBox(height: 8),
            Text('저장된 URI: ${_persistedUri?.toString() ?? "(없음)"}'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: _loading ? null : _pick,
                  child: const Text('폴더 선택 & 저장'),
                ),
                OutlinedButton(
                  onPressed: _loading ? null : _refresh,
                  child: const Text('권한 유효성 재검사'),
                ),
                OutlinedButton(
                  onPressed: _loading ? null : _listFiles,
                  child: const Text('파일 목록 예시'),
                ),
              ],
            ),
            if (_loading) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      ),
    );
  }
}
