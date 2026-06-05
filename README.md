# easycheck

EasyCheck는 생명과학 연구원이 96-well plate 실험 설계, 농도 계산, 실험 노트, 결과 관리를 모바일에서 수행할 수 있도록 만드는 Flutter 앱 프로젝트입니다.

## 문서

- [Flutter 개발 플랜](docs/flutter-development-plan.md)
- [MVP 우선 개발 로드맵](docs/mvp-first-roadmap.md)
- [수동 QA 체크리스트](docs/manual-qa-checklist.md)
- [UI 확인 가이드](docs/ui-screenshots.md)

## 현재 구현 상태

첫 구현 단계로 Flutter 앱의 기본 골격과 96-well plate 화면 프로토타입을 추가했습니다.

- Flutter 앱 진입점과 iOS 메모앱 느낌의 기본 테마
- iOS/Android 로컬 실행을 위한 Flutter platform scaffold
- 실험 노트 홈 화면, 검색, 생성, 수정, 복제, 삭제와 JSON 파일 기반 로컬 저장
- 실험별 96-well plate grid, 행/열/범위 선택, 그룹 색상 지정, JSON 파일 기반 plate layout 저장
- 선택한 well의 농도, 측정 결과, 결과 단위, 메모, 분석 제외 여부를 기록하는 상세 카드
- Plate layout과 well별 측정 결과를 메모/엑셀/구글시트에 붙여넣을 수 있는 TSV 내보내기
- 시작 농도, 희석 배수, 단계 수, 반복 well 수, 방향을 입력해 plate에 적용하는 희석 계산 Builder
- 실험, plate, well, well group 도메인 모델 초안

## 로컬 실행

Flutter SDK가 설치된 환경에서 아래 명령을 실행합니다.

```bash
flutter pub get
flutter run
```

### iOS/Android에서 실행 확인

이 저장소에는 iOS/Android platform scaffold가 포함되어 있습니다. 실행 가능한 기기나 시뮬레이터가 연결된 상태에서 아래 명령으로 대상 기기를 확인하고 앱을 실행합니다.

```bash
flutter devices
flutter run -d <device-id>
```

Linux CI 환경에서는 iOS 빌드/실행을 수행할 수 없으므로, macOS에서 iPhone Simulator 또는 실제 iPhone으로 별도 확인합니다.

## 테스트

```bash
flutter test
```

### Flutter SDK가 없을 때

현재 환경에서 `flutter: command not found`가 발생하면 아래 bootstrap 스크립트로 프로젝트 로컬 Flutter SDK를 설치합니다. 설치 위치는 기본적으로 `.tool/flutter`이며 git에는 포함되지 않습니다.

```bash
scripts/bootstrap_flutter.sh
export PATH="$PWD/.tool/flutter/bin:$PATH"
flutter pub get
flutter test
```

만약 네트워크 정책 때문에 Google Storage 또는 GitHub 접근이 `403`으로 막히면, Flutter 공식 SDK를 수동으로 설치한 뒤 `flutter`가 PATH에 잡히도록 설정하고 같은 테스트 명령을 실행합니다.

## CI

GitHub Actions의 [Flutter CI](.github/workflows/flutter.yml)는 push와 pull request에서 `flutter pub get`, `dart format --set-exit-if-changed .`, `flutter analyze`, `flutter test`를 실행합니다.
