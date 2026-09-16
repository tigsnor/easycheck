# PlateNote 알파 배포 및 실제 기기 테스트 가이드

이 문서는 개발자 검증을 통과한 PlateNote를 연구자가 실제 휴대폰에서 반복 테스트하기 위한 절차입니다.

## 1. 알파 빌드 기준

- Flutter 버전은 저장소의 `.fvmrc`에 고정합니다.
- 앱 버전과 빌드 번호는 `pubspec.yaml`의 `version`을 사용합니다.
- Android와 iOS의 앱 식별자는 현재 `com.easycheck.easycheck`입니다.
- 알파 데이터는 실제 연구 원본의 유일한 저장소로 사용하지 않습니다. 매 테스트 종료 후 전체 JSON 백업을 별도로 보관합니다.

## 2. GitHub Actions에서 빌드 확인

PR 또는 `work`/`main` 브랜치 push가 발생하면 다음 작업이 실행됩니다.

1. `Format, analyze, and test`: 포맷, 정적 분석, 전체 테스트
2. `Build Android alpha APK`: 설치 가능한 debug APK 생성
3. `Build iOS Simulator app`: 코드 서명이 필요 없는 iOS Simulator 앱 생성

Actions 실행 화면의 `Artifacts`에서 다음 파일을 받을 수 있습니다.

- `platenote-android-alpha-<run number>`: Android 실제 기기 설치용 `platenote-android-alpha.apk`
- `platenote-ios-simulator-<run number>`: macOS의 iPhone Simulator 확인용 ZIP

각 artifact에는 앱 버전·commit·run number를 기록한 `BUILD_INFO.txt`와 파일 무결성을 확인하는 `SHA256SUMS.txt`가 포함됩니다.

산출물은 14일 동안 보관합니다. 실패한 품질 검사 뒤에는 플랫폼 빌드를 실행하지 않습니다.

## 3. Android 실제 기기 설치

1. GitHub Actions의 성공한 실행에서 Android alpha artifact를 다운로드하고 압축을 풉니다.
2. Android 기기에서 테스트용 APK 설치를 허용합니다.
3. `platenote-android-alpha.apk`를 기기로 전송해 설치합니다.
4. 기존 알파 버전 위에 설치하면 같은 application ID의 앱 데이터가 유지됩니다.
5. 저장 형식 변경을 검증할 때는 먼저 전체 백업을 만든 후 삭제·재설치 테스트도 별도로 수행합니다.

> Debug APK는 내부 알파 테스트 전용입니다. 외부 배포나 스토어 출시에는 release keystore와 Play Console 설정이 필요합니다.

## 4. iPhone에서 테스트하는 방법

CI의 iOS artifact는 Simulator 전용이므로 실제 iPhone에 직접 설치할 수 없습니다. 실제 iPhone 알파 테스트는 다음 중 하나가 필요합니다.

### 권장: TestFlight

1. Apple Developer Program과 App Store Connect 앱을 준비합니다.
2. Xcode에서 Runner의 Team과 고유 Bundle ID를 설정합니다.
3. Archive를 생성해 App Store Connect에 업로드합니다.
4. 여자친구분의 Apple ID를 내부 또는 외부 테스터로 초대합니다.
5. 새 빌드마다 `pubspec.yaml`의 build number를 증가시킵니다.

### 개발 중 임시 설치

Mac에 iPhone을 연결하고 Xcode의 개인/개발 팀으로 Runner를 서명해 `flutter run` 또는 Xcode Run을 사용합니다. 무료 개인 팀은 서명 유효기간과 기능 제한이 있어 반복 알파 테스트에는 TestFlight가 더 적합합니다.

## 5. 첫 실제 기기 테스트 시나리오

각 시나리오는 테스트 전 전체 백업을 만들고, 완료 후 결과와 불편 사항을 기록합니다.

1. 새 실험 생성 → 앱 종료 → 재실행 → 데이터 유지 확인
2. 96-well Plate에서 행·열·범위 선택 → 그룹 색상 지정
3. 희석 계산 적용 → 농도와 반복 well 배치 확인
4. Well 결과와 메모 입력 → 저장 상태 확인 → 재실행 후 유지 확인
5. Plate reader 결과 행렬 붙여넣기 → 오류 셀과 적용 개수 확인
6. Plate TSV를 Files/AirDrop/메일로 공유하고 Excel 또는 Google Sheets에서 열기
7. 전체 JSON 백업 공유 → 테스트 데이터 삭제 → Files/iCloud에서 선택해 복원
8. 화면 회전, 키보드 표시, 작은 화면에서 버튼이나 입력란이 가려지지 않는지 확인
9. 비행기 모드에서 생성·수정·백업이 동작하는지 확인
10. 30개 이상의 실험을 만든 뒤 검색과 목록 스크롤이 불편하지 않은지 확인

## 6. 피드백 기록 원칙

버그와 사용성 문제는 다음 정보를 함께 기록합니다.

- 앱 버전과 GitHub Actions run number
- 기기 모델, OS 버전, 화면 방향
- 사용한 실험 유형과 데이터 규모
- 재현 순서
- 기대 결과와 실제 결과
- 데이터 손실 여부
- 가능하면 개인정보나 연구 기밀을 제거한 화면 녹화 또는 스크린샷

우선순위는 다음과 같이 분류합니다.

- **P0**: 데이터 손실, 잘못된 농도/희석 계산, 앱 실행 불가
- **P1**: 핵심 작업을 완료할 수 없음, 저장·복원·내보내기 실패
- **P2**: 우회 가능한 불편, 작은 화면 오버플로, 이해하기 어려운 문구
- **P3**: 색상, 간격, 애니메이션 등 개선 제안

P0/P1 문제를 해결하기 전에는 해당 알파 버전을 실제 실험 기록의 주 도구로 사용하지 않습니다.
