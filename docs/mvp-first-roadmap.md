# PlateNote MVP 우선 개발 로드맵

## 방향성

### 현재 우선순위 원칙

이 문서의 구현 세부사항보다 [단일 사용자 우선 출시 계획](single-user-release-plan.md)을 우선 적용합니다. 현재 목표는 계정·클라우드·협업 플랫폼이 아니라, 한 명의 연구자가 한 기기에서 데이터를 안전하게 기록하고 복구할 수 있는 앱입니다.

단일 사용자 버전이 실제 실험에서 검증될 때까지 cloud sync, 팀 권한, 결제, 고급 IC50 자동화는 개발 순서에서 제외합니다.

PlateNote는 처음부터 모든 고급 분석 기능을 넣기보다, 연구원이 실제 실험 중 바로 사용할 수 있는 기본 앱을 먼저 완성한 뒤 단계적으로 고도화합니다.

우선 목표는 다음 흐름이 끊기지 않게 만드는 것입니다.

1. 앱을 열고 실험 노트를 만든다.
2. 실험 제목, 유형, 프로젝트, 메모를 기록한다.
3. 96-well plate를 열어 well layout을 만든다.
4. 실험군을 색상과 라벨로 구분한다.
5. 1000, 500, 250처럼 serial dilution 농도를 자동 계산해 적용한다.
6. 앱을 껐다 켜도 실험과 plate 정보가 유지된다.
7. 최소한 CSV 또는 PDF로 plate layout을 내보낸다.

이 흐름이 완성되기 전까지 IC50, plate reader import, cloud sync, OCR 같은 고급 기능은 뒤로 미룹니다.

## 1차 목표: 기본적으로 작동하는 앱

### 1. 개발/검증 환경 고정

- Flutter SDK 기준을 stable channel로 고정합니다.
- GitHub Actions에서 다음 명령이 자동으로 실행되게 합니다.
  - `flutter pub get`
  - `dart format --set-exit-if-changed .`
  - `flutter analyze`
  - `flutter test`
- 로컬과 CI에서 같은 검증 명령을 사용합니다.

완료 기준:
- PR마다 GitHub Actions가 실행됩니다.
- format, analyze, test가 모두 통과해야 merge할 수 있습니다.

### 2. 실험 노트 로컬 저장

현재 실험 노트 생성/수정/삭제는 화면 state에만 저장되는 인메모리 방식입니다. 기본 앱이 되려면 앱을 껐다 켜도 데이터가 남아야 합니다.

작업:
- Drift 또는 SQLite 기반 로컬 DB 추가
- `experiments` table 추가
- Experiment repository 추가
- 홈 화면의 인메모리 list를 repository 기반으로 교체
- 생성, 수정, 복제, 삭제 결과를 DB에 저장

완료 기준:
- 실험을 만들고 앱을 재시작해도 목록에 남아 있습니다.
- 수정한 제목과 메모가 유지됩니다.
- 삭제한 실험이 다시 나타나지 않습니다.

### 3. Plate layout 로컬 저장

현재 plate editor는 demo layout을 보여주는 prototype입니다. 다음 단계에서는 실험별 plate layout을 저장해야 합니다.

작업:
- `plates`, `wells`, `well_groups` table 추가
- 실험별 기본 96-well plate 생성
- well 선택 정보 저장
- well별 group, role, concentration, unit 저장
- plate editor가 demo data가 아니라 repository data를 사용하게 변경

완료 기준:
- 실험마다 plate layout을 따로 가집니다.
- well에 입력한 농도와 그룹이 앱 재시작 후에도 유지됩니다.

### 4. Plate 편집 기본 기능

작업:
- 단일 well 선택
- 행/열 선택
- 사각형 범위 선택
- 선택 영역에 group 지정
- group 색상과 짧은 라벨 표시
- 선택 well/group 상세 bottom sheet

완료 기준:
- 사용자가 A1:B7 같은 범위를 선택할 수 있습니다.
- 선택 영역에 `Drug A`, `Control`, `Blank` 같은 그룹을 지정할 수 있습니다.
- plate에서 색상과 라벨로 조건을 구분할 수 있습니다.

### 5. Serial dilution 적용 UI

현재 dilution 계산 로직은 있지만 사용자가 직접 입력하는 UI가 없습니다.

작업:
- 시작 농도 입력
- 단위 선택
- 희석 배수 입력
- 단계 수 입력
- 방향 선택
- 0 control 포함 여부 선택
- 미리보기 표시
- 선택 영역에 적용

완료 기준:
- 사용자가 `1000`, `2배`, `6단계`, `0 control 포함`을 입력하면 `1000 → 500 → 250 → 125 → 62.5 → 31.25 → 0`이 생성됩니다.
- 생성된 농도를 선택한 well 범위에 적용할 수 있습니다.

### 6. 기본 export

작업:
- Plate layout CSV export
- 실험 노트와 plate 요약 PDF export 초안

완료 기준:
- 실험자가 plate layout을 파일로 공유할 수 있습니다.

## 2차 목표: 실험 기록 앱으로 고도화

기본 기능이 안정화된 뒤 아래 기능을 추가합니다.

### 사진/파일 첨부

- plate 사진 첨부
- 현미경 사진 첨부
- CSV, Excel, PDF 파일 첨부
- 첨부 파일 caption 저장

### 템플릿

- 자주 쓰는 plate layout 저장
- CCK-8 2-fold dilution 기본 템플릿
- ELISA standard curve 템플릿
- Drug screening duplicate 템플릿

### 실수 방지

- control 없음 경고
- blank 없음 경고
- replicate 부족 경고
- 농도 단위 혼용 경고
- edge well 사용 표시

### Pipetting plan

- [x] stock concentration 입력
- [x] final concentration series 연결
- [x] final volume per well 입력
- [x] well별 stock/diluent volume 계산
- [x] master mix 및 overage 계산
- [x] 저용량·선택 well 부족 경고
- [ ] 단계별 실행 체크리스트와 serial transfer 계산

## 3차 목표: 분석 앱으로 확장

### Plate reader 결과 import

- CSV import
- Excel import
- well coordinate mapping
- raw value 저장

### 기본 분석

- blank correction
- control normalization
- replicate 평균
- 표준편차
- CV 계산
- 농도별 chart

### 고급 분석

- dose-response curve
- IC50 계산
- outlier 표시

## 4차 목표: 백업과 협업

### 백업

- JSON export/import
- 수동 백업/복원

### Cloud sync

- Supabase 또는 Firebase PoC
- 사용자가 명시적으로 켠 경우에만 sync
- 연구 데이터 보호 정책 정리

## 단일 사용자 기준 추천 구현 순서

현재까지 실험 CRUD, Plate 저장·편집, 희석, 직접 stock 희석 피펫팅 계획, 결과 입력, 기본 분석, TSV 내보내기와 JSON 백업이 구현되어 있습니다. 다음 순서에서는 기능 수보다 실제 기기 안정성과 데이터 복구를 우선합니다.

1. GitHub Actions artifact로 실제 기기 알파 QA 수행
2. 알파 테스트에서 발견된 P0/P1 사용성 문제 수정
3. Atomic write, 마지막 정상본 보관, 손상 감지와 schema migration
4. 사진·파일 첨부와 첨부파일 백업
5. Plate 템플릿 저장·적용
6. CSV 결과 파일 선택·preview·import 이력
7. Serial transfer와 단계별 실행 체크리스트
8. Android internal testing과 iOS TestFlight 배포

## 명시적으로 연기하는 범위

- 사용자 계정과 로그인
- Cloud sync와 여러 사용자 협업
- 팀·연구실 권한 관리
- 서버 기반 공유와 결제
- 고급 dose-response fitting과 IC50 자동화

이 범위는 단일 사용자 버전이 최소 2주 실제 실험에서 안정적으로 사용된 뒤 다시 평가합니다.
