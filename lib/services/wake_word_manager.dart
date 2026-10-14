import 'package:porcupine_flutter/porcupine.dart';
import 'package:porcupine_flutter/porcupine_manager.dart';
import 'package:porcupine_flutter/porcupine_error.dart';

class WakeWordManager {
  // 🔴 [수정 필수] Picovoice Console에서 발급받은 AccessKey를 붙여넣으세요.
  // https://console.picovoice.ai/ 에서 무료 계정 생성 후 AccessKey 복사
  final String accessKey = const String.fromEnvironment('PICOVOICE_ACCESS_KEY');

  PorcupineManager? _porcupineManager;
  final Function(int) onWakeWordDetected; // 감지됐을 때 실행될 콜백 함수
  bool isListening = false;

  WakeWordManager({required this.onWakeWordDetected});

  // 초기화 함수
  Future<void> init() async {
    try {
      // 🟡 임시: 영어 내장 키워드 사용 (한국어 model 파일 없음)
      // ppn 파일(ko)과 model 파일(en) 언어 불일치 해결
      _porcupineManager = await PorcupineManager.fromBuiltInKeywords(
        accessKey,
        [BuiltInKeyword.JARVIS], // "자비스" 발음 쉬움
        onWakeWordDetected,
        errorCallback: _onError,
      );

      // TODO: 한국어 사용하려면
      // 1. 백엔드에 영어(en) ppn 파일 요청 (예: "yoonmin_en_android_v4_0_0.ppn")
      // 2. 또는 한국어 model 파일(.pv) 다운로드: https://github.com/Picovoice/porcupine/tree/master/lib/common
      //    → porcupine_params_ko.pv 다운로드 후 assets/models/에 추가
      //    → PorcupineManager.fromKeywordPaths(accessKey, [...], modelPath: "assets/models/porcupine_params_ko.pv")

      // ✨ 커스텀 키워드: "윤여민" (한국어 model 파일 추가 후 사용)
      // _porcupineManager = await PorcupineManager.fromKeywordPaths(
      //   accessKey,
      //   ["assets/keywords/윤여민_ko_android_v4_0_0.ppn"],
      //   onWakeWordDetected,
      //   errorCallback: _onError,
      //   modelPath: "assets/models/porcupine_params_ko.pv", // 한국어 model 파일
      // );

      print("🦔 웨이크 워드 엔진 준비 완료 (호출어: JARVIS)");
    } on PorcupineException catch (err) {
      print("❌ 웨이크 워드 초기화 에러: ${err.message}");
      print("👉 AccessKey가 올바른지, 패키지 ID가 콘솔에 등록되었는지 확인하세요.");
      print("👉 https://console.picovoice.ai/ 에서 AccessKey 발급 후 붙여넣으세요.");
      rethrow; // 에러를 상위로 전파하여 UI에서 처리
    } catch (e) {
      print("❌ 기타 에러: $e");
      rethrow;
    }
  }

  // 듣기 시작
  Future<void> startListening() async {
    try {
      if (_porcupineManager != null && !isListening) {
        await _porcupineManager!.start();
        isListening = true;
        print("👂 [대기 중] 호출어를 말해주세요...");
      }
    } catch (e) {
      print("❌ 듣기 시작 실패: $e");
    }
  }

  // 듣기 중지 (마이크 충돌 방지)
  Future<void> stopListening() async {
    try {
      if (_porcupineManager != null && isListening) {
        await _porcupineManager!.stop();
        isListening = false;
        print("🛑 웨이크 워드 감지 중단");
      }
    } catch (e) {
      print("❌ 중지 실패: $e");
    }
  }

  void _onError(PorcupineException error) {
    print("❌ 에러 발생: ${error.message}");
  }

  // 메모리 해제 (앱 종료 시)
  Future<void> dispose() async {
    if (_porcupineManager != null) {
      await _porcupineManager!.delete();
    }
  }
}
