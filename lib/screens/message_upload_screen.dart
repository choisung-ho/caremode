// lib/screens/message_upload_screen.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:caremode/services/storage_service.dart';
import '../services/message_storage_service.dart';

/// 메시지 ?�로???�면
class MessageUploadScreen extends StatefulWidget {
  final String userCode;

  const MessageUploadScreen({super.key, required this.userCode});

  @override
  State<MessageUploadScreen> createState() => _MessageUploadScreenState();
}

class _MessageUploadScreenState extends State<MessageUploadScreen> {
  final MessageStorageService _messageService = MessageStorageService();
  final StorageService _storageService = StorageService();

  List<MessageItem> _messages = [];
  Set<String> _selectedIds = {};
  bool _isLoading = true;
  bool _isUploading = false;
  double _uploadProgress = 0;

  StreamSubscription<List<MessageItem>>? _messageSub;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await _messageService.init();

      // 메시지 ?�트�?구독
      _messageSub = _messageService.messageStream.listen((messages) {
        if (mounted) {
          setState(() {
            _messages = messages;
          });
        }
      });

      if (mounted) {
        setState(() {
          _messages = _messageService.messages.toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('??MessageUploadScreen 초기???�패: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _messageSub?.cancel();
    super.dispose();
  }

  /// ?�택??메시지 ?�로??(개별 JSON ?�일�??�로??
  Future<void> _uploadSelectedMessages() async {
    if (_selectedIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('?�로?�할 메시지�??�택?�주?�요'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isUploading = true;
      _uploadProgress = 0;
    });

    try {
      // ?�택??메시지??가?�오�?
      final selectedMessages = _messages
          .where((m) => _selectedIds.contains(m.id))
          .toList();

      int uploadedCount = 0;
      int totalCount = selectedMessages.length;
      List<String> uploadedIds = [];

      for (final message in selectedMessages) {
        try {
          // 개별 메시지 ?�로??
          await _uploadSingleMessage(message);
          uploadedIds.add(message.id);
          uploadedCount++;

          // 진행�??�데?�트
          if (mounted) {
            setState(() {
              _uploadProgress = (uploadedCount / totalCount) * 100;
            });
          }
        } catch (e) {
          debugPrint('??메시지 ?�로???�패: ${message.id} - $e');
        }
      }

      // ?�로?�된 메시지 ?�시
      if (uploadedIds.isNotEmpty) {
        _messageService.markMultipleAsUploaded(uploadedIds);
      }

      setState(() {
        _uploadProgress = 100;
        _selectedIds.clear();
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('??$uploadedCount�?메시지 ?�로???�료'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('??메시지 ?�로???�패: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('?�로???�패: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadProgress = 0;
        });
      }
    }
  }

  /// 개별 메시지�?Firebase Storage???�로??(백엔???�식)
  Future<void> _uploadSingleMessage(MessageItem message) async {
    // 1. ?�이???�성 (백엔???�청 ?�식)
    final smsData = {
      "media_type": "sms",
      "user_id": widget.userCode,
      "sender_phone": message.title, // 발신??
      "message_body": message.content, // 메시지 ?�용
      "app_name": message.appName, // ???�름 (카카?�톡, 문자 ??
      "package_name": message.packageName,
      "received_at": message.timestamp.toIso8601String(),
    };

    // 2. JSON 문자?�로 변??
    String jsonString = jsonEncode(smsData);

    // 3. ?�일�??�성 (?�니?�하�?
    String timestamp = message.timestamp.millisecondsSinceEpoch.toString();
    String fileName = "sms_$timestamp.json";

    // 4. ?�로??(경로: user_XXX/source/sms_logs/{fileName})
    final uploadResult = await _storageService.uploadString(
      jsonString,
      'sms_logs',
      fileName: fileName,
      contentType: 'application/json',
    );

    debugPrint('??SMS ?�로???�공: ${uploadResult.path}');

    // 5. Firestore??메�??�이???�??(?�택?�항)
    final downloadUrl = uploadResult.downloadUrl;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userCode)
        .collection('sms_uploads')
        .add({
          'fileName': fileName,
          'storagePath': uploadResult.path,
          'downloadUrl': downloadUrl,
          'sender': message.title,
          'appName': message.appName,
          'uploadedAt': FieldValue.serverTimestamp(),
          'receivedAt': Timestamp.fromDate(message.timestamp),
        });
  }

  /// 모든 미업로드 메시지 ?�택
  void _selectAllUnuploaded() {
    setState(() {
      _selectedIds = _messages
          .where((m) => !m.isUploaded)
          .map((m) => m.id)
          .toSet();
    });
  }

  /// ?�택 ?�제
  void _clearSelection() {
    setState(() {
      _selectedIds.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const color = Colors.purple;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        title: Row(
          children: [
            Icon(Icons.message_rounded, color: color, size: 24),
            const SizedBox(width: 8),
            const Text(
              '메시지',
              style: TextStyle(
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
          if (_messages.isNotEmpty) ...[
            IconButton(
              icon: const Icon(Icons.select_all),
              tooltip: '?�체 ?�택',
              onPressed: _selectAllUnuploaded,
            ),
            if (_selectedIds.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.deselect),
                tooltip: '?�택 ?�제',
                onPressed: _clearSelection,
              ),
          ],
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '?�로고침',
            onPressed: () {
              setState(() {
                _messages = _messageService.messages.toList();
              });
            },
          ),
        ],
      ),
      body: _buildBody(scheme, isDark, color),
      bottomNavigationBar: _selectedIds.isNotEmpty
          ? _buildBottomBar(scheme, color)
          : null,
    );
  }

  Widget _buildBody(ColorScheme scheme, bool isDark, Color color) {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: color),
            const SizedBox(height: 16),
            Text(
              '메시지 로드 �?..',
              style: TextStyle(color: scheme.onSurface.withOpacity(0.1)),
            ),
          ],
        ),
      );
    }

    if (_messages.isEmpty) {
      return _buildEmptyView(scheme, color);
    }

    return Column(
      children: [
        // ?�단 ?�보
        _buildHeader(scheme, isDark, color),

        // ?�로??진행 ?�시
        if (_isUploading) _buildUploadProgress(scheme, color),

        // 메시지 리스??
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _messages.length,
            itemBuilder: (context, index) {
              final message = _messages[index];
              return _buildMessageCard(message, scheme, isDark, color);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(ColorScheme scheme, bool isDark, Color color) {
    final unuploadedCount = _messages.where((m) => !m.isUploaded).length;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? color.withOpacity(0.1) : color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.notifications_active, color: color, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '감�???메시지',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: scheme.onSurface,
                    fontFamily: 'Pyeongtaek',
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '�?${_messages.length}�?(미업로드: $unuploadedCount�?',
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.onSurface.withOpacity(0.1),
                  ),
                ),
              ],
            ),
          ),
          if (_selectedIds.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${_selectedIds.length}�??�택',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildUploadProgress(ColorScheme scheme, Color color) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: color),
              ),
              const SizedBox(width: 12),
              Text(
                '?�로??�?.. ${_uploadProgress.toStringAsFixed(0)}%',
                style: TextStyle(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: _uploadProgress / 100,
            color: color,
            backgroundColor: color.withOpacity(0.1),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageCard(
    MessageItem message,
    ColorScheme scheme,
    bool isDark,
    Color color,
  ) {
    final isSelected = _selectedIds.contains(message.id);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: message.isUploaded
              ? null
              : () {
                  setState(() {
                    if (isSelected) {
                      _selectedIds.remove(message.id);
                    } else {
                      _selectedIds.add(message.id);
                    }
                  });
                },
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isSelected
                  ? color.withOpacity(0.1)
                  : message.isUploaded
                  ? scheme.surfaceContainerHighest.withOpacity(0.1)
                  : scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected
                    ? color
                    : message.isUploaded
                    ? Colors.green.withOpacity(0.1)
                    : scheme.outline.withOpacity(0.1),
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                // ?�택 체크박스 ?�는 ?�로???�태
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: message.isUploaded
                        ? Colors.green.withOpacity(0.1)
                        : isSelected
                        ? color.withOpacity(0.1)
                        : _getAppColor(message.appName).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: message.isUploaded
                      ? const Icon(
                          Icons.cloud_done,
                          color: Colors.green,
                          size: 20,
                        )
                      : isSelected
                      ? Icon(Icons.check, color: color, size: 20)
                      : Icon(
                          _getAppIcon(message.appName),
                          color: _getAppColor(message.appName),
                          size: 20,
                        ),
                ),
                const SizedBox(width: 12),
                // 메시지 ?�용
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              message.title,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: message.isUploaded
                                    ? scheme.onSurface.withOpacity(0.1)
                                    : scheme.onSurface,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _getAppColor(
                                message.appName,
                              ).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              message.appName,
                              style: TextStyle(
                                fontSize: 10,
                                color: _getAppColor(message.appName),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        message.content,
                        style: TextStyle(
                          fontSize: 13,
                          color: message.isUploaded
                              ? scheme.onSurface.withOpacity(0.1)
                              : scheme.onSurface.withOpacity(0.1),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        message.formattedDate,
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurface.withOpacity(0.1),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyView(ColorScheme scheme, Color color) {
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
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.message_outlined, size: 50, color: color),
            ),
            const SizedBox(height: 24),
            Text(
              '감�???메시지가 ?�습?�다',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: scheme.onSurface,
                fontFamily: 'Pyeongtaek',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '알림을 감지하면 여기에 표시됩니다',
              style: TextStyle(
                fontSize: 14,
                color: scheme.onSurface.withOpacity(0.6),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '문자, 카카오톡 등의 메시지가\n자동으로 수집됩니다',
              style: TextStyle(
                fontSize: 13,
                color: scheme.onSurface.withOpacity(0.5),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar(ColorScheme scheme, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: ElevatedButton.icon(
          onPressed: _isUploading ? null : _uploadSelectedMessages,
          icon: _isUploading
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.cloud_upload),
          label: Text(
            _isUploading ? '업로드 중..' : '${_selectedIds.length}개 메시지 업로드',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            minimumSize: const Size(double.infinity, 56),
          ),
        ),
      ),
    );
  }

  IconData _getAppIcon(String appName) {
    switch (appName) {
      case '문자':
        return Icons.sms;
      case '카카오톡':
        return Icons.chat_bubble;
      case '텔레그램':
        return Icons.send;
      case 'WhatsApp':
        return Icons.call;
      case '인스타그램':
        return Icons.camera_alt;
      case 'Facebook':
        return Icons.facebook;
      case 'LINE':
        return Icons.message;
      default:
        return Icons.notifications;
    }
  }

  Color _getAppColor(String appName) {
    switch (appName) {
      case '문자':
        return Colors.blue;
      case '카카오톡':
        return const Color(0xFFFEE500);
      case '텔레그램':
        return const Color(0xFF0088CC);
      case 'WhatsApp':
        return const Color(0xFF25D366);
      case '인스타그램':
        return const Color(0xFFE4405F);
      case 'Facebook':
        return const Color(0xFF1877F2);
      case 'LINE':
        return const Color(0xFF00B900);
      default:
        return Colors.grey;
    }
  }
}
