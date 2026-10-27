# PlateNote

PlateNote는 생명과학 연구원이 96-well plate 실험 설계, 농도 계산, 실험 노트, 결과 관리를 모바일에서 수행할 수 있도록 만드는 Flutter 앱 프로젝트입니다.

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
- [연구 업무 기능 개선안](docs/research-workflow-roadmap.md)

## 현재 구현 상태

현재는 실제 기기 알파 테스트를 위한 단일 사용자 MVP 기능을 중심으로 구현하고 있습니다.

- Flutter 앱 진입점과 iOS 메모앱 느낌의 기본 테마
- iOS/Android 로컬 실행을 위한 Flutter platform scaffold
- 실험 노트 홈 화면, 검색, 생성, 수정, 복제, 삭제 확인/실행 취소와 versioned JSON 로컬 저장
- 새 실험 노트 생성·상세 편집에서 세포수 정보를 구조화해 저장하고, 기존 메모 기반 `세포수:` 기록도 자동 인식
- 임시 파일 교체, 직전 정상본 보관, 손상 파일 자동 복구·사용자 안내와 legacy JSON migration
- 모든 실험·연결 Plate·사용자 템플릿을 PlateNote v2 백업 JSON으로 복사·파일 공유하고, Files/iCloud에서 선택해 사전 검증·실패 rollback과 함께 ID 기준 병합 복원하는 전체 백업
- 손상된 로컬 파일을 읽지 못해도 외부 백업에서 전체 복구하며, 기존 원본을 보존하고 검증된 데이터로 전환
- 실험별 96-well plate grid, 화면 맞춤·단계별 확대·가로 스크롤, 행/열/범위 선택, 그룹 색상 지정, JSON 파일 기반 plate layout 저장
- well을 길게 누른 채 드래그하는 사각형 범위 선택, 즉시 드래그 선택 모드와 가장자리 자동 스크롤
- Plate 저장 중/완료 상태 표시와 최근 20개 변경에 대한 실행 취소
- 현재 Plate 설정을 결과값 없이 로컬 템플릿으로 저장·이름 변경·삭제하고, 기본 CCK-8 예시 또는 저장 템플릿을 Plate 편집기/새 실험 생성 시 재적용
- 선택한 well의 농도, 측정 결과, 결과 단위, 메모, 분석 제외 여부를 기록하는 상세 카드
- 실험 사진·원본 파일 첨부: 설명·촬영/측정 시각·Plate/well 연결, 사진 미리보기와 원본 공유, 첨부 포함 백업·복원 및 무결성 검사
- 결과 연속 입력: 행/열 방향 선택, 저장 성공 후 다음 well 이동, 실패 시 입력 유지·재시도, 미저장 입력 폐기 확인
- Excel/Plate reader의 A-H × 1-12 결과 행렬을 붙여넣거나 CSV/TSV/TXT 파일로 불러와 여러 well에 일괄 입력
- 가져오기 전 전체 well 배치·값 비교 목록, 신규/덮어쓰기/동일/유지 표시와 변경 항목 필터, 정확한 기존값·적용 후 값·단위 확인
- Plate layout과 well별 측정 결과를 메모/엑셀/구글시트에 붙여넣거나 파일로 공유할 수 있는 TSV 내보내기
- 시작 농도, 희석 배수, 단계 수, 반복 well 수, 방향과 0 농도 대조군 역할을 선택해 plate에 적용하는 희석 계산 Builder
- Stock 농도, well당 부피, 여유분을 이용한 직접 희석·연속 희석 피펫팅 계획, 단계별 잔여량과 저용량 경고
- 실험 유형별 기본 실행 단계, 사용자 단계 추가, 단계별 시작·경과·완료 시각을 저장하는 실험 실행 체크리스트와 타이머
- 완료된 실험 노트의 수정 잠금, 수정 사유 및 변경 이력 기록
- 실험 노트의 미저장 변경 표시와 뒤로가기 시 저장·폐기 선택
- 실험 목록 불러오기 실패 시 데이터 보존 안내와 다시 시도, 아래로 당겨 새로고침
- 완료된 실험의 Plate 배치·결과를 변경 없이 확인하는 읽기 전용 화면
- Plate 그룹·희석·well 결과·import·템플릿 변경과 실행 취소 이력 기록
- Plate 선택·범위·확대 상태를 UI에서 분리한 테스트 가능한 상태관리 controller
- Plate 상단은 저장 상태·실행 취소·더보기로 단순화하고 선택 작업은 하단 상황별 액션으로 제공
- Plate grid 중심 작업 화면과 요약·준비 점검·well 상세·분석·이력 바텀시트 분리
- 실험과 Plate에 공통 저장됨·미저장·저장 중·저장 실패 상태와 실패 재시도 제공
- 입력·희석 오류는 작업 화면 안에, 로드·저장 오류는 유지되는 재시도 UI로 구분해 표시
- 실험 담당자와 시약 제조사·catalog·lot, 장비 model·serial 정보를 저장하는 사용 자원 기록
- Blank/Control 누락, 반복 well 부족, 농도 단위 혼용, 일부 결과 누락을 알려주는 실험 준비 점검
- 분석 제외 well을 반영한 농도별 평균·표본 표준편차·CV·blank 보정·control 대비 정규화
- 그룹·결과 단위별 Blank/Control well 지정, 자동/수동 기준과 실제 좌표 표시, 기준 누락·제외·단위 변경 시 계산 중단 및 안내
- 농도별 기초 차트와 분석 reference/series를 포함한 TSV 복사·파일 공유
- 완료된 Plate와 well 선택 중에도 상단에서 분석 조회·내보내기 가능, 개별 well 역할에 따라 처리군·대조군 구분
- 빈 Plate를 기본으로 생성하고, 기본 예시·사용자 템플릿은 선택 시에만 적용
- 실험 설계 복제: 기본정보·단계·자원·Plate 배치를 복사하고 결과·메모·타이머·완료·이력 초기화
- 48dp 기본 Plate 작업 보기, 좌표 표시, 배치/결과 전환과 미입력·분석 제외 표시

실험실 작업 관점의 개선 내역과 다음 우선순위는 [UI·UX 점검](docs/lab-ux-review.md)에 정리했습니다.
- 실험, plate, well, well group 도메인 모델 초안

## 현재 개발 우선순위

1. 실제 iPhone/Android 기기에서 신규 실험 생성, Plate 편집, 희석 계산, 결과 입력, 백업/복원 수동 QA 반복
2. 실제 기기 피드백 기반 키보드/바텀시트/작은 화면 사용성 개선
3. Android internal testing과 iOS TestFlight 배포 준비
4. 실험 사진·파일 첨부
5. 변경 이력 비교 화면과 복원 전 미리보기
6. 고급 분석 기능(IC50, 통계 검정 등) 검토

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
