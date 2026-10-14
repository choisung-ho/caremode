import 'dart:async';
import 'dart:convert'; // ✅ jsonEncode 사용

import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthService {
  // - Android 에뮬레이터: http://10.0.2.2:8000
  // - 실제 폰(USB/와이파이): PC의 IP (예: http://10.0.2.2:8000)
  // 필요하면 실행 시 덮어쓰기:
  // flutter run --dart-define=AUTH_API_BASE_URL=http://10.0.2.2:8000
  static const String baseUrl = String.fromEnvironment(
    'AUTH_API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  final Dio _dio;
  final FirebaseAuth _firebaseAuth;
  final FlutterSecureStorage _storage;

  /// 마지막 실패 사유(화면에서 그대로 보여주기 용도)
  String? lastError;

  AuthService({
    Dio? dio,
    FirebaseAuth? firebaseAuth,
    FlutterSecureStorage? storage,
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(
               baseUrl: baseUrl,
               connectTimeout: const Duration(seconds: 8),
               sendTimeout: const Duration(seconds: 15),
               receiveTimeout: const Duration(seconds: 15),
               headers: const {
                 'Accept': 'application/json',
                 'Content-Type': 'application/json', // ✅ JSON 전송 명시
               },
             ),
           ),
       _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
       _storage = storage ?? const FlutterSecureStorage();

  Future<bool> signup({
    required String email,
    required String password,
    required String name,
    required String gender,
    required String birth,
    required String phone,
    required double homeLat,
    required double homeLng,
    required int role,
    String? fcmToken,
    String? guardianId,
  }) async {
    try {
      lastError = null;
      final payload = <String, dynamic>{
        'email': email,
        'password': password,
        'name': name,
        'gender': gender,
        'birth': birth,
        'phone': phone,
        'homeLat': homeLat,
        'homeLng': homeLng,
        'role': role,
        if (fcmToken != null && fcmToken.isNotEmpty) 'fcmToken': fcmToken,
        if (guardianId != null && guardianId.isNotEmpty)
          'guardianId': guardianId,
      };

      // 🔍 디버그: 전송 데이터 확인
      // Authentication payload is never logged.
      final response = await _dio
          .post('/signup', data: payload)
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 201) return true;

      lastError =
          '회원가입 실패: status=${response.statusCode} ${response.data ?? ''}'
              .trim();
      debugPrint('Signup failed: $lastError');
      return false;
    } on DioException catch (e) {
      final msg = _prettyDioError(e);
      lastError = msg;
      debugPrint('Signup failed: $lastError');
      return false;
    } on TimeoutException {
      lastError = '요청 시간 초과(타임아웃). 서버가 켜져있는지 확인하세요.';
      debugPrint('Signup failed: $lastError');
      return false;
    } catch (e) {
      lastError = '알 수 없는 오류: $e';
      debugPrint('Signup failed: $lastError');
      return false;
    }
  }

  /// FastAPI -> Custom Token 발급 -> Firebase 로그인
  /// 성공 시 role(1=보호자, 2=대상자) 반환
  Future<int?> login({required String email, required String password}) async {
    try {
      lastError = null;
      // ✅ 새 구조: 로그인은 FirebaseAuth가 직접 담당
      final cred = await _firebaseAuth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = cred.user;
      if (user == null) {
        lastError = '로그인 실패: Firebase user가 null입니다.';
        return null;
      }

      // ✅ role은 Firestore(DB/users/[가입이메일])에서 조회
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(email)
          .get();

      if (!doc.exists) {
        lastError = '사용자 데이터가 없습니다: users/$email';
        return null;
      }

      final data = doc.data();
      final rawRole = data?['role'] ?? data?['userRole'] ?? data?['roleId'];
      final int? role = switch (rawRole) {
        int v => v,
        num v => v.toInt(),
        String v => int.tryParse(v),
        _ => null,
      };

      if (role == null) {
        lastError = 'role 값이 올바르지 않습니다: $rawRole';
        return null;
      }

      await _storage.write(key: 'user_role', value: role.toString());
      return role;
    } on FirebaseAuthException catch (e) {
      // Firebase 로그인 에러 메시지 매핑
      if (e.code == 'user-not-found') {
        lastError = '계정을 찾을 수 없습니다.';
      } else if (e.code == 'wrong-password') {
        lastError = '비밀번호가 틀렸습니다.';
      } else if (e.code == 'invalid-email') {
        lastError = '이메일 형식이 올바르지 않습니다.';
      } else if (e.code == 'user-disabled') {
        lastError = '비활성화된 계정입니다.';
      } else {
        lastError =
            '[${e.code}] ${e.message ?? '로그인 실패(FirebaseAuthException)'}';
      }
      debugPrint('Login failed: $lastError');
      return null;
    } catch (e) {
      lastError = '알 수 없는 오류: $e';
      debugPrint('Login failed: $lastError');
      return null;
    }
  }

  String _prettyDioError(DioException e) {
    // 서버가 응답한 에러(422/400/500 등)
    final status = e.response?.statusCode;
    final responseData = e.response?.data;
    if (status != null) {
      final path = e.requestOptions.path;
      final detail = _extractServerDetail(responseData);
      if (detail != null && detail.isNotEmpty) {
        return '서버 오류(HTTP $status) $path: $detail';
      }
      return '서버 오류(HTTP $status) $path';
    }

    // 연결 단계에서 막히는 케이스(지금 로그의 connectTimeout)
    if (e.type == DioExceptionType.connectionTimeout) {
      return '서버 연결 시간 초과(connectTimeout). 서버 실행/주소/방화벽 확인 (${baseUrl})';
    }
    if (e.type == DioExceptionType.connectionError) {
      return '서버 연결 실패(connectionError). 서버 실행/주소/포트 확인 (${baseUrl})';
    }
    if (e.type == DioExceptionType.receiveTimeout) {
      return '서버 응답 지연(receiveTimeout). 서버가 느리거나 응답이 없음';
    }

    return e.message ?? e.toString();
  }

  String? _extractServerDetail(dynamic responseData) {
    if (responseData == null) return null;

    // FastAPI validation error 형태: {"detail": [...]} 또는 {"detail": "..."}
    if (responseData is Map) {
      final detail = responseData['detail'];
      if (detail == null) return responseData.toString();
      return detail.toString();
    }

    // string/html
    if (responseData is String) {
      final v = responseData.trim();
      if (v.isEmpty) return null;
      // 너무 길면 잘라서 스낵바 폭주 방지
      return v.length > 300 ? '${v.substring(0, 300)}…' : v;
    }

    return responseData.toString();
  }

  Future<void> logout() async {
    await _firebaseAuth.signOut();
    await _storage.delete(key: 'user_role');
  }
}
