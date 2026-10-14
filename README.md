# Caremode

고령자와 보호자의 돌봄 흐름을 지원하는 Flutter 모바일 앱 소스입니다. 사용자 역할에 따른 화면, Firebase 인증, 음성 대화와 파일 업로드, 복약 알림·통화 녹음 연동 구현을 포함합니다.

## 주요 구성

- `lib/screens`: 로그인·가입·역할 선택, 대상자/보호자 홈, 음성 대화, 미디어·메시지 업로드, 복약 알림
- `lib/services/auth_service.dart`: FastAPI 인증 API와 Firebase Custom Token 로그인
- `lib/screens/voice_chat_screen.dart`: WebSocket 오디오 송수신
- `lib/services/call_recording_service.dart`: Android SAF 폴더 접근·전화 상태 구독·녹음 파일 업로드
- `lib/services`: FCM, 파일·미디어 저장, 백그라운드 작업과 호출어 처리

## 실행 준비

Flutter/Dart 환경은 `pubspec.yaml`의 SDK 조건(`^3.10.1`)을 확인하세요. Firebase 프로젝트와 호환되는 백엔드는 직접 준비해야 합니다. 이 저장소에는 서버·운영 설정·사용자 데이터가 포함되지 않습니다.

```bash
flutter pub get
# FlutterFire CLI를 설치한 환경에서 프로젝트 설정 생성
flutterfire configure
flutter run --dart-define=AUTH_API_BASE_URL=http://10.0.2.2:8000 --dart-define=PICOVOICE_ACCESS_KEY=YOUR_LOCAL_KEY
```

FlutterFire 설정으로 `lib/firebase_options.dart`와 플랫폼 Firebase 설정을 생성하세요. 이 파일들은 저장소에서 제외했습니다. Android 에뮬레이터의 `10.0.2.2`는 개발 PC를 가리킵니다. 실기기에서는 접근 가능한 개발 서버 주소가 필요하며 음성·미디어 서비스의 연결 주소도 환경에 맞게 설정해야 합니다. 실제 연결과 기기 기능의 성공은 별도 검증이 필요합니다.

Picovoice 키는 `--dart-define`으로 전달합니다. 개인 이름을 사용한 커스텀 호출어 모델과 폰트 바이너리는 포함하지 않았으며 Flutter 기본 폰트로 표시됩니다. 통화 파일·전화 상태·알림 접근 기능은 Android 버전과 권한, 기기 제조사에 따라 다릅니다.

## 포트폴리오 설명

핵심은 역할 기반 사용자 흐름, 인증 실패·타임아웃 처리, 마이크·WebSocket 자원 관리, Android 파일 권한과 업로드 연동입니다. 화면 수보다 실제 담당 기능과 기기에서 해결한 문제를 설명하는 것이 좋습니다.

현재 업로드는 기존 로컬 소스를 보관·정리한 것으로 전체 앱 빌드·서비스 연결·운영 성과를 검증한 릴리스는 아닙니다. 인증 payload 로그와 하드코딩된 호출어 키는 업로드본에서 제거했습니다.
