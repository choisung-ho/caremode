// lib/screens/media_upload_screen.dart
import 'package:flutter/material.dart';
import 'media_file_list_screen.dart';
import 'message_upload_screen.dart';

/// 미디어 업로드 메인 화면
/// 동영상, 사진, 음성, 메시지 카테고리별 업로드 버튼 제공
class MediaUploadScreen extends StatelessWidget {
  final String userCode;

  const MediaUploadScreen({super.key, required this.userCode});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    const headerBg = Color(0xFFD9E6DF);
    const videoBg = Color(0xFFD9E9F7);
    const photoBg = Color(0xFFDFF1E1);
    const audioBg = Color(0xFFF6EBD9);
    const messageBg = Color(0xFFE8DFF4);

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        title: const Text(
          '서버 업로드',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontFamily: 'Pyeongtaek',
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 헤더 설명
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? scheme.primary.withOpacity(0.12) : headerBg,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: (isDark ? scheme.primary : const Color(0xFF9EB6AB))
                        .withOpacity(0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.cloud_upload_outlined,
                      color: isDark
                          ? scheme.onSurface
                          : const Color(0xFF2C8B72),
                      size: 32,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '파일 서버 업로드',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: scheme.onSurface,
                              fontFamily: 'Pyeongtaek',
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '카테고리를 선택하여 파일을 업로드하세요',
                            style: TextStyle(
                              fontSize: 13,
                              color: scheme.onSurface.withOpacity(0.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              _buildCategoryButton(
                context: context,
                icon: Icons.videocam_rounded,
                title: '동영상',
                subtitle: '.mp4 파일 업로드',
                color: const Color(0xFF3B7EDC),
                background: videoBg,
                isDark: isDark,
                onTap: () => _navigateToFileList(context, MediaType.video),
              ),
              const SizedBox(height: 14),

              _buildCategoryButton(
                context: context,
                icon: Icons.photo_rounded,
                title: '사진',
                subtitle: '.jpg, .png 파일 업로드',
                color: const Color(0xFF2E9A51),
                background: photoBg,
                isDark: isDark,
                onTap: () => _navigateToFileList(context, MediaType.photo),
              ),
              const SizedBox(height: 14),

              _buildCategoryButton(
                context: context,
                icon: Icons.mic_rounded,
                title: '음성',
                subtitle: '.m4a, .mp3, .wav 파일 업로드',
                color: const Color(0xFFE99B2A),
                background: audioBg,
                isDark: isDark,
                onTap: () => _navigateToFileList(context, MediaType.audio),
              ),
              const SizedBox(height: 14),

              _buildCategoryButton(
                context: context,
                icon: Icons.message_rounded,
                title: '메시지',
                subtitle: '감지된 알림 메시지 업로드',
                color: const Color(0xFF8B5BC5),
                background: messageBg,
                isDark: isDark,
                onTap: () => _navigateToMessageUpload(context),
              ),

              const SizedBox(height: 20),

              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 18,
                      color: scheme.onSurface.withOpacity(0.5),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '이미 업로드된 파일은 중복 업로드가 방지됩니다',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurface.withOpacity(0.5),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryButton({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required Color background,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: isDark ? color.withOpacity(0.1) : background,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withOpacity(0.2), width: 1),
          ),
          child: Row(
            children: [
              // 아이콘 둥근 사각형 배경
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: color.withOpacity(isDark ? 0.3 : 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, size: 28, color: color),
              ),
              const SizedBox(width: 16),
              // 텍스트
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: scheme.onSurface,
                        fontFamily: 'Pyeongtaek',
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
              // 화살표
              Icon(
                Icons.arrow_forward_ios,
                color: color.withOpacity(0.7),
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _navigateToFileList(BuildContext context, MediaType type) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            MediaFileListScreen(userCode: userCode, mediaType: type),
      ),
    );
  }

  void _navigateToMessageUpload(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MessageUploadScreen(userCode: userCode),
      ),
    );
  }
}
