# Caremode — 고령자와 보호자를 위한 돌봄 모바일 앱

고령자와 보호자의 역할에 맞춰 화면을 제공하고, 음성 대화·복약 알림·미디어와 통화 파일 연동을 연결한 Flutter 모바일 앱 프로젝트입니다.

## 해결하려던 문제

돌봄 앱은 대상자의 단순한 이용 흐름과 보호자의 관리 흐름을 함께 고려해야 합니다. 인증과 역할에 따른 화면 전환, 음성 입력, 파일 권한과 업로드를 각각의 서비스로 나눠 구성했습니다.

## 주요 구현

- **사용자 역할:** 가입·로그인, 역할 선택, 대상자·보호자 홈 화면
- **인증:** 백엔드 가입 API, Firebase Auth 로그인과 Firestore 역할 조회, 보안 저장소
- **음성 대화:** 마이크 입력과 WebSocket 오디오 송수신, 대화 화면의 자원 관리
- **생활 지원:** 복약 알림, FCM 알림, 미디어·메시지 업로드
- **Android 연동:** SAF 폴더 접근, 전화 상태 구독과 녹음 파일 업로드

## 구조와 기술

| 경로 | 역할 |
| --- | --- |
| `lib/screens/` | 가입·역할·홈·음성 대화·업로드·알림 화면 |
| `lib/services/auth_service.dart` | 가입 API 호출, Firebase 로그인, 역할 조회 |
| `lib/screens/voice_chat_screen.dart` | WebSocket 오디오 대화 |
| `lib/services/call_recording_service.dart` | Android 파일·전화 상태 연동 |
| `lib/services/fcm_manager.dart` | 알림 토큰 관리와 서버/Firestore 연동 |

Flutter·Dart, Firebase Auth·Firestore·FCM·Storage, Dio, WebSocket과 Android 파일 접근 라이브러리를 사용합니다.

## 설계와 문제 해결

- **네트워크 실패 처리:** 가입·로그인 요청의 타임아웃과 실패 원인을 구분합니다.
- **역할별 화면 흐름:** 로그인 결과와 역할 정보를 앱 화면 전환에 연결합니다.
- **기기 자원 관리:** 마이크·WebSocket·전화 상태 구독의 시작과 종료를 서비스 단위로 다룹니다.
- **권한과 파일 접근:** Android SAF로 사용자가 허용한 폴더를 읽고 녹음 파일을 업로드합니다.
- **로그 보호:** FCM 토큰·사용자 식별 정보·통화 번호·알림과 대화 본문·파일 주소를 진단 로그에 출력하지 않도록 정리했습니다.

## 실행

`pubspec.yaml`의 Dart SDK 조건은 `^3.10.1`입니다. Flutter, Firebase 프로젝트와 호환되는 백엔드를 준비합니다.

```bash
git clone https://github.com/choisung-ho/caremode.git
cd caremode
flutter pub get
flutterfire configure
flutter run --dart-define=AUTH_API_BASE_URL=http://10.0.2.2:8000 --dart-define=PICOVOICE_ACCESS_KEY=YOUR_LOCAL_KEY
```

`flutterfire configure`로 `lib/firebase_options.dart`와 플랫폼 Firebase 설정을 생성합니다. `10.0.2.2`는 Android 에뮬레이터에서 개발 PC를 가리키며, 실기기에서는 접근 가능한 백엔드 주소가 필요합니다. 음성·미디어 서비스 연결도 실행 환경에 맞춰 설정합니다.

## 구현 범위와 한계

이 저장소는 모바일 클라이언트입니다. 백엔드와 운영 Firebase 설정, 실제 사용자 자료는 포함하지 않습니다. 통화 파일·전화 상태·알림 접근은 Android 버전·권한·제조사에 따라 달라집니다. 사용자별 커스텀 호출어 모델은 별도로 준비해야 합니다. 실제 기기에서의 전체 서비스 연결과 기능 검증은 릴리스 전에 확인해야 합니다.

[검증 기록](docs/PUBLIC_VALIDATION.md)에서 이번 확인 범위를 볼 수 있습니다.
