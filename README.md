# easycheck

EasyCheck는 생명과학 연구원이 96-well plate 실험 설계, 농도 계산, 실험 노트, 결과 관리를 모바일에서 수행할 수 있도록 만드는 Flutter 앱 프로젝트입니다.

현재 제품 우선순위는 **한 명의 연구자가 한 기기에서 오프라인으로 안정적으로 사용할 수 있는 버전**입니다. Cloud sync, 협업, 계정과 고급 제품 기능은 단일 사용자 버전이 실제 실험에서 검증된 뒤로 미룹니다.

## 문서

- [Flutter 개발 플랜](docs/flutter-development-plan.md)
- [단일 사용자 우선 출시 계획](docs/single-user-release-plan.md)
- [MVP 우선 개발 로드맵](docs/mvp-first-roadmap.md)
- [수동 QA 체크리스트](docs/manual-qa-checklist.md)
- [알파 배포 및 실제 기기 테스트 가이드](docs/alpha-testing-guide.md)
- [알파 피드백 템플릿](docs/alpha-feedback-template.md)
- [기본 결과 분석 계산 기준](docs/basic-analysis-method.md)
- [피펫팅 계획 계산 기준](docs/pipetting-plan-method.md)
- [로컬 데이터 안전 기준](docs/local-data-safety.md)
- [UI 확인 가이드](docs/ui-screenshots.md)

## 현재 구현 상태

첫 구현 단계로 Flutter 앱의 기본 골격과 96-well plate 화면 프로토타입을 추가했습니다.

- Flutter 앱 진입점과 iOS 메모앱 느낌의 기본 테마
- iOS/Android 로컬 실행을 위한 Flutter platform scaffold
- 실험 노트 홈 화면, 검색, 생성, 수정, 복제, 삭제 확인/실행 취소와 versioned JSON 로컬 저장
- 임시 파일 교체, 직전 정상본 보관, 손상 파일 자동 복구·사용자 안내와 legacy JSON migration
- 모든 실험과 연결 Plate를 버전형 JSON으로 복사·파일 공유하고, Files/iCloud에서 선택해 사전 검증·실패 rollback과 함께 ID 기준 병합 복원하는 전체 백업
- 실험별 96-well plate grid, 화면 맞춤·단계별 확대·가로 스크롤, 행/열/범위 선택, 그룹 색상 지정, JSON 파일 기반 plate layout 저장
- Plate 저장 중/완료 상태 표시와 최근 20개 변경에 대한 실행 취소
- 선택한 well의 농도, 측정 결과, 결과 단위, 메모, 분석 제외 여부를 기록하는 상세 카드
- Excel/Plate reader의 A-H × 1-12 결과 행렬을 붙여넣어 여러 well에 일괄 입력
- Plate layout과 well별 측정 결과를 메모/엑셀/구글시트에 붙여넣거나 파일로 공유할 수 있는 TSV 내보내기
- 시작 농도, 희석 배수, 단계 수, 반복 well 수, 방향을 입력해 plate에 적용하는 희석 계산 Builder
- Stock 농도, well당 부피, 여유분을 이용한 농도별 master mix 피펫팅 계획과 저용량 경고
- Blank/Control 누락, 반복 well 부족, 농도 단위 혼용, 일부 결과 누락을 알려주는 실험 준비 점검
- 분석 제외 well을 반영한 농도별 평균·표본 표준편차·CV·blank 보정·control 대비 정규화
- 농도별 기초 차트와 분석 reference/series를 포함한 TSV 복사·파일 공유
- 실험, plate, well, well group 도메인 모델 초안

## 현재 개발 우선순위

1. 실제 기기에서 전체 수동 QA 수행
2. 로컬 저장의 atomic write, 자동 복구와 schema migration
3. 실험 사진·파일 첨부
4. Plate 템플릿
5. CSV 결과 파일 import
6. 단계별 피펫팅·실험 실행 체크리스트
7. Android internal testing과 iOS TestFlight 배포

진행률은 개발자 검증, 실제 기기 알파 테스트, 단일 사용자 MVP, 단일 사용자 실험실 사용 가능도의 네 단계로 관리합니다. 세부 완료 기준은 [단일 사용자 우선 출시 계획](docs/single-user-release-plan.md)을 따릅니다.

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

GitHub Actions의 [Flutter CI](.github/workflows/flutter.yml)는 고정된 Flutter 버전으로 포맷, 정적 분석, 전체 테스트를 실행한 뒤 Android 알파 APK와 iOS Simulator 앱을 빌드해 14일간 artifact로 제공합니다. 실제 기기 설치 절차는 [알파 테스트 가이드](docs/alpha-testing-guide.md)를 확인합니다.
