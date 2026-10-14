import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences 기반 경량 버퍼 유틸
/// - SMS/알림, GPS 등 가벼운 데이터를 즉시 업로드하지 않고 로컬에 잠깐 모았다가
///   WorkManager 주기 작업 시 한꺼번에 전송할 때 사용.
class BufferService {
  static const String smsBufferKey = 'sms_buffer';
  static const String gpsBufferKey = 'gps_buffer';

  const BufferService();

  /// key에 문자열 한 건을 추가
  Future<void> append(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(key) ?? <String>[];
    list.add(value);
    await prefs.setStringList(key, list);
  }

  /// key에 쌓여 있는 모든 문자열을 조회 (비우지 않음)
  Future<List<String>> peek(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(key) ?? <String>[];
  }

  /// key에 쌓여 있는 모든 문자열을 가져오고, 저장소에서는 제거
  Future<List<String>> takeAndClear(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(key) ?? <String>[];
    await prefs.remove(key);
    return list;
  }

  /// 지정 키 전체 삭제
  Future<void> clear(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }

  /// SMS/알림 전용 헬퍼
  Future<void> appendSms(String value) => append(smsBufferKey, value);
  Future<List<String>> takeSmsAndClear() => takeAndClear(smsBufferKey);

  /// GPS 전용 헬퍼
  Future<void> appendGps(String value) => append(gpsBufferKey, value);
  Future<List<String>> takeGpsAndClear() => takeAndClear(gpsBufferKey);
}
