# 윈도우에서 아이폰 설치

프로젝트 루트에는 `.github/workflows/ios-build.yml`과 `Goyo/` 폴더가 함께 있어야 합니다.
워크플로는 GitHub의 Mac 서버에서 GoyoBrowser를 실제 아이폰용으로 빌드하고,
Sideloadly가 서명할 수 있는 `GoyoBrowser-unsigned.ipa`를 생성합니다.
Apple 비밀번호나 인증서를 GitHub에 등록할 필요가 없습니다.

## 빌드

1. 프로젝트를 저장소의 `main` 브랜치에 올립니다.
2. 저장소의 Actions에서 **Goyo iPhone IPA**를 선택합니다.
3. **Run workflow**를 누릅니다. main에 프로젝트가 올라가면 자동 빌드도 실행됩니다.
4. 성공한 실행의 Artifacts에서 **GoyoBrowser-IPA**를 다운로드하고 압축을 풉니다.

## 설치

1. https://sideloadly.io/ 에서 Windows용 Sideloadly와 공식 안내에 따른 iTunes·iCloud를 설치합니다.
2. 아이폰을 USB로 연결하고 ‘이 컴퓨터를 신뢰’를 누릅니다.
3. Sideloadly에서 `GoyoBrowser-unsigned.ipa`를 선택하고 본인 Apple 계정으로 설치합니다.
4. 아이폰에서 요청하면 개발자 모드를 켜고 개발자 앱을 신뢰합니다.

이 IPA는 공부 타이머·투두·캘린더·앱 내부 웹 필터를 포함하는 GoyoBrowser입니다.
기존 앱 전체를 잠그는 기능은 별도의 Goyo 타깃에서 Family Controls와 App Group
프로비저닝을 설정한 빌드로 사용합니다. GoyoBrowser IPA를 설치해도 해당 권한은 생기지 않습니다.

자동 빌드 설정과 IPA 포장 스크립트는 준비되었습니다.
실제 Xcode 빌드 성공 여부와 IPA 결과는 GitHub Actions 실행으로 확인해야 합니다.
