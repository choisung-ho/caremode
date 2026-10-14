// lib/services/identity_upload_service.dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:camera/camera.dart';
import 'package:intl/intl.dart';

/// 사용자 인식 데이터 업로드 서비스
/// 온보딩 시 수집하는 얼굴 사진, 음성 샘플을 Firebase Storage에 저장
///
/// 폴더 구조:
/// identity/
///   ├── faces/{userCode}/     - 얼굴 사진
///   └── voices/{userCode}/    - 음성 샘플
class IdentityUploadService {
  static final FirebaseStorage _storage = FirebaseStorage.instance;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// 얼굴 사진 업로드
  /// 파일명: {userCode}_face_{날짜}_{시간}_{순번}.jpg
  ///
  /// 반환: 성공 시 업로드된 파일 URL 리스트, 실패 시 에러 메시지
  static Future<Map<String, dynamic>> uploadFacePhotos({
    required String userCode,
    required List<XFile> photos,
    Function(int current, int total, double progress)? onProgress,
  }) async {
    if (photos.isEmpty) {
      return {'success': false, 'error': '사진을 한 장 이상 첨부해주세요'};
    }

    final List<String> uploadedUrls = [];
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());

    try {
      for (int i = 0; i < photos.length; i++) {
        final photo = photos[i];
        final fileName = '${userCode}_face_${timestamp}_${i + 1}.jpg';
        final storagePath = 'identity/faces/$userCode/$fileName';

        debugPrint('📸 얼굴 사진 업로드 시작: $fileName');

        final ref = _storage.ref().child(storagePath);
        final bytes = await photo.readAsBytes();

        final uploadTask = ref.putData(
          bytes,
          SettableMetadata(contentType: 'image/jpeg'),
        );

        // 진행률 콜백
        uploadTask.snapshotEvents.listen((snapshot) {
          final progress = snapshot.bytesTransferred / snapshot.totalBytes;
          onProgress?.call(i + 1, photos.length, progress * 100);
        });

        await uploadTask;
        final downloadUrl = await ref.getDownloadURL();
        uploadedUrls.add(downloadUrl);

        debugPrint('✅ 얼굴 사진 업로드 완료: $fileName');
      }

      // Firestore에 메타데이터 저장
      await _firestore
          .collection('users')
          .doc(userCode)
          .collection('identity')
          .doc('face_data')
          .set({
            'type': 'face_photos',
            'photoUrls': uploadedUrls,
            'photoCount': uploadedUrls.length,
            'uploadedAt': FieldValue.serverTimestamp(),
            'status': 'pending', // pending → processing → done
          });

      debugPrint('✅ 얼굴 사진 ${uploadedUrls.length}장 업로드 완료');

      return {
        'success': true,
        'urls': uploadedUrls,
        'message': '얼굴 사진 ${uploadedUrls.length}장 등록 완료',
      };
    } catch (e) {
      debugPrint('❌ 얼굴 사진 업로드 실패: $e');
      return {'success': false, 'error': '업로드 실패: $e'};
    }
  }

  /// 음성 샘플 업로드
  /// 파일명: {userCode}_voice_{날짜}_{시간}.m4a
  ///
  /// 반환: 성공 시 업로드된 파일 URL, 실패 시 에러 메시지
  static Future<Map<String, dynamic>> uploadVoiceSample({
    required String userCode,
    required File audioFile,
    Function(double progress)? onProgress,
  }) async {
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final extension = audioFile.path.split('.').last;
    final fileName = '${userCode}_voice_$timestamp.$extension';
    final storagePath = 'identity/voices/$userCode/$fileName';

    try {
      debugPrint('🎤 음성 샘플 업로드 시작: $fileName');

      final ref = _storage.ref().child(storagePath);
      final uploadTask = ref.putFile(
        audioFile,
        SettableMetadata(contentType: 'audio/$extension'),
      );

      // 진행률 콜백
      uploadTask.snapshotEvents.listen((snapshot) {
        final progress =
            (snapshot.bytesTransferred / snapshot.totalBytes) * 100;
        onProgress?.call(progress);
      });

      await uploadTask;
      final downloadUrl = await ref.getDownloadURL();

      // Firestore에 메타데이터 저장
      await _firestore
          .collection('users')
          .doc(userCode)
          .collection('identity')
          .doc('voice_data')
          .set({
            'type': 'voice_sample',
            'voiceUrl': downloadUrl,
            'fileName': fileName,
            'uploadedAt': FieldValue.serverTimestamp(),
            'status': 'pending', // pending → processing → done
          });

      debugPrint('✅ 음성 샘플 업로드 완료: $fileName');

      return {'success': true, 'url': downloadUrl, 'message': '음성 샘플 등록 완료'};
    } catch (e) {
      debugPrint('❌ 음성 샘플 업로드 실패: $e');
      return {'success': false, 'error': '업로드 실패: $e'};
    }
  }

  /// 사용자 인식 데이터 등록 상태 확인
  static Future<Map<String, dynamic>> getIdentityStatus(String userCode) async {
    try {
      final faceDoc = await _firestore
          .collection('users')
          .doc(userCode)
          .collection('identity')
          .doc('face_data')
          .get();

      final voiceDoc = await _firestore
          .collection('users')
          .doc(userCode)
          .collection('identity')
          .doc('voice_data')
          .get();

      return {
        'faceRegistered': faceDoc.exists,
        'faceStatus': faceDoc.data()?['status'],
        'voiceRegistered': voiceDoc.exists,
        'voiceStatus': voiceDoc.data()?['status'],
      };
    } catch (e) {
      debugPrint('❌ 인식 데이터 상태 확인 실패: $e');
      return {'faceRegistered': false, 'voiceRegistered': false};
    }
  }
}
