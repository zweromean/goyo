# 윈도우에서 전체 고요 설치

전체 앱의 스크린 타임 기능은 **Goyo** 타깃에 있습니다. GoyoBrowser는 동반 브라우저 버전입니다.

## 자동 빌드

Actions의 **Goyo iPhone IPA**가 두 타깃을 빌드합니다.
- **Goyo-IPA**: 전체 앱 + Shield Configuration, Shield Action, Device Activity 확장. 미서명.
- **GoyoBrowser-IPA**: 공부 도구 + 내장 웹 필터. 미서명, 시스템 스크린 타임 잠금 없음.
- **Goyo-simulator-screens**: 전체 앱의 시뮬레이터 홈·공부 화면 실행 검사 결과.

무료 계정으로 GoyoBrowser를 Sideloadly에서 서명할 수 있습니다. 전체 Goyo를 같은 방식으로 다시 서명해도 Family Controls 권한이 생기지 않습니다.

## 스크린 타임이 작동하는 서명

Apple Developer Program 계정에서 전체 앱 및 확장 3개의 명시적 App ID, 같은 App Group, Family Controls가 포함된 프로비저닝을 준비합니다.
직접 설치용 개발 또는 등록 기기용 프로파일에는 설치할 아이폰의 UDID가 포함되어 있어야 합니다.
TestFlight/App Store 배포를 사용할 때에는 Apple의 Family Controls 배포 권한과 배포 프로파일이 별도로 필요합니다.

저장소 Settings → Secrets and variables → Actions에 아래 값을 보관합니다. 인증서나 계정 비밀번호를 공개 소스나 대화에 넣지 마세요.

| Actions secret | 내용 |
|---|---|
| GOYO_P12_BASE64 | 서명 인증서와 개인 키를 내보낸 p12의 base64 |
| GOYO_P12_PASSWORD | p12의 비밀번호. Apple 계정 비밀번호 아님 |
| GOYO_PROFILES_ZIP_BASE64 | 전체 앱과 확장 3개의 .mobileprovision 네 파일을 묶은 ZIP의 base64 |
| GOYO_SIGNING_IDENTITY | p12 안 인증서의 코드 서명 identity 이름 또는 SHA-1 |

필요하면 repository variables의 GOYO_BUNDLE_ID와 GOYO_APP_GROUP을 본인의 등록 값으로 설정합니다. 기본 값은 app.goyo.detox와 group.app.goyo.detox입니다.

Actions → **Goyo signed iPhone app** → Run workflow를 실행하면 실제 기기용 전체 앱을 빌드하고 네 프로파일을 검증한 뒤 서명합니다.
완료 결과는 **Goyo-signed-iPhone**의 Goyo-signed.ipa입니다. 이 서명은 아직 계정 자료가 없어서 실행하지 않았습니다.
서명 스크립트는 Family Controls가 없는 프로파일을 거부하며 권한을 삭제해서 설치 가능하게 만들지 않습니다.
서명 파일은 임시 디렉터리에서 사용하고 작업 종료 시 인증서 키체인과 자료를 제거합니다.

## 아이폰에서

서명된 전체 앱을 설치하고 필요하면 개발자 모드와 개발자 앱 신뢰를 설정합니다.
고요의 ‘앱 잠금’에서 스크린 타임을 연결하고 잠글 앱·허용 앱을 선택합니다.
전화·문자가 필요하면 허용 앱에 포함해주세요. 이후 공부 중 허용 앱만 사용 옵션을 켤 수 있습니다.
