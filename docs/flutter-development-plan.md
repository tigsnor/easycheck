# EasyCheck Flutter 개발 플랜

## 1. 제품 비전

EasyCheck는 생명과학 연구원이 96-well plate 기반 실험을 아이폰 메모앱처럼 빠르게 기록하고, 농도 배치와 serial dilution 계산, 실험군 관리, 사진 기록, 결과 분석까지 한곳에서 관리하는 모바일 우선 실험 노트 앱입니다.

초기 타깃은 iPhone 앱이며, Flutter를 사용해 Android, iPad, Web 확장 가능성을 열어둡니다. 제품의 핵심 가치는 실험 중 손으로 plate 뚜껑이나 종이에 쓰던 정보를 모바일에서 실수 없이 설계, 기록, 재사용하게 만드는 것입니다.

## 2. 핵심 사용자 시나리오

### 2.1 실험 전 설계

1. 연구원이 새 실험 노트를 생성합니다.
2. 실험 유형을 선택합니다. 예: CCK-8, MTT, ELISA, dose-response, custom.
3. 96-well plate 템플릿을 선택합니다.
4. 가로, 세로, 사각형 드래그로 well 범위를 선택합니다.
5. 선택 영역에 실험군 이름, 색상, 처리 물질, 농도 단위, replicate 수를 지정합니다.
6. 시작 농도와 희석 배수를 입력한 뒤 serial dilution을 자동 계산합니다.
7. 앱이 control, blank, replicate 누락 여부를 점검합니다.
8. 필요한 경우 pipetting plan을 확인합니다.

### 2.2 실험 중 기록

1. plate 화면을 열고 색상과 라벨로 조건을 확인합니다.
2. 특정 well 또는 그룹을 탭하면 하단 sheet에서 상세 정보를 봅니다.
3. 실험 중 발생한 이슈를 메모합니다. 예: bubble 발생, edge well 제외, incubation 시간 변경.
4. plate 사진, 현미경 사진, 실험 결과 사진을 첨부합니다.

### 2.3 실험 후 분석과 공유

1. plate reader 결과 CSV 또는 Excel 파일을 가져옵니다.
2. 앱이 well layout과 결과값을 매칭합니다.
3. blank 보정, control 대비 생존율, 평균, 표준편차를 계산합니다.
4. dose-response curve와 IC50 계산을 수행합니다.
5. PDF, CSV, Excel, PNG 이미지로 내보냅니다.
6. 템플릿으로 저장해 다음 실험에 재사용합니다.

## 3. 기능 요구사항

### 3.1 실험 노트 관리

- 실험 노트 생성, 수정, 삭제, 복제 기능을 제공합니다.
- 제목, 날짜, 프로젝트, 실험자, 실험 유형, 태그, 자유 메모를 저장합니다.
- 아이폰 메모앱과 유사하게 최근 실험 목록, 폴더, 검색 중심 UI를 제공합니다.
- 실험별로 여러 plate를 연결할 수 있도록 설계합니다.
- 실험 상태를 `draft`, `planned`, `in_progress`, `completed`, `archived`로 관리합니다.

### 3.2 Plate layout 편집

- 기본 96-well plate를 지원합니다. 구조는 A-H 8행, 1-12 12열입니다.
- 향후 6-well, 12-well, 24-well, 48-well, 384-well plate 확장이 가능해야 합니다.
- well 선택 방식을 지원합니다.
  - 단일 well 선택
  - 행 전체 선택
  - 열 전체 선택
  - 사각형 범위 드래그 선택
  - 다중 범위 선택
  - 선택 영역 복사, 붙여넣기, 삭제
- well 내부에는 최소 정보만 표시합니다.
  - 색상
  - 짧은 그룹 라벨
  - 농도 숫자 또는 control 라벨
- 상세 정보는 하단 bottom sheet에서 표시합니다.

### 3.3 실험군과 색상 관리

- 선택한 well 범위에 실험군을 지정합니다.
- 실험군 속성은 다음을 포함합니다.
  - 그룹명
  - 색상
  - 짧은 라벨
  - 처리 물질 또는 sample 이름
  - 농도 단위
  - replicate 설정
  - control/blank/sample/treatment 역할
  - 메모
- 색상만으로 구분하지 않고 라벨을 함께 제공합니다.
- 기본 그룹 유형을 제공합니다.
  - Treatment
  - Blank
  - Negative control
  - Positive control
  - Vehicle control
  - Untreated control
  - Standard
  - Sample

### 3.4 농도 입력과 serial dilution 계산

- 각 well별 농도 숫자와 단위를 저장합니다.
- 그룹 또는 선택 범위 단위로 농도를 일괄 입력할 수 있습니다.
- serial dilution 계산 기능을 제공합니다.
  - 시작 농도
  - 희석 배수
  - 단계 수
  - 방향: 위에서 아래, 아래에서 위, 왼쪽에서 오른쪽, 오른쪽에서 왼쪽
  - 반복 column/row 수
  - 마지막 0 concentration 또는 control 추가 여부
- 예시 계산: 시작 농도 1000, 희석 배수 2, 아래 방향, control 포함 시 `1000, 500, 250, 125, 62.5, 31.25, 0`을 생성합니다.
- 계산 결과 적용 전 미리보기를 제공합니다.
- 자동 계산 후 사용자가 개별 well 값을 수동 수정할 수 있습니다.
- 단위 변환을 지원합니다.
  - M, mM, µM, nM, pM
  - mg/mL, µg/mL, ng/mL
  - %, X, custom unit

### 3.5 부피와 pipetting plan

- stock concentration, final concentration, final volume per well, replicate 수를 바탕으로 필요한 stock volume과 diluent volume을 계산합니다.
- serial dilution 기반 pipetting plan을 생성합니다.
- well별 투입 단계와 총 필요량을 보여줍니다.
- master mix 계산을 지원합니다.
- dead volume 또는 overage 비율을 설정할 수 있습니다. 예: 10% extra.
- 피펫팅 plan은 체크리스트 형태로 표시해 실험 중 완료 표시가 가능해야 합니다.

### 3.6 사진과 파일 첨부

- 실험 노트에 사진을 첨부합니다.
  - plate 사진
  - 현미경 사진
  - 결과 사진
  - 기타 실험 기록 이미지
- 파일을 첨부합니다.
  - CSV
  - Excel
  - PDF
  - 이미지
- 사진별 캡션과 촬영 시간을 저장합니다.
- 향후 OCR 또는 plate 이미지 인식 확장을 고려해 원본 이미지를 보존합니다.

### 3.7 결과 입력과 분석

- well별 결과값을 수동 입력할 수 있습니다.
- CSV 또는 Excel plate reader 결과를 가져올 수 있습니다.
- 결과값 유형을 지원합니다.
  - absorbance
  - fluorescence
  - luminescence
  - raw count
  - custom numeric value
- 분석 기능을 제공합니다.
  - blank 보정
  - control 대비 normalization
  - replicate 평균
  - 표준편차
  - coefficient of variation
  - outlier 표시
  - dose-response curve
  - IC50 계산
- 분석 결과는 그래프와 표로 표시합니다.

### 3.8 템플릿과 재사용

- plate layout을 템플릿으로 저장합니다.
- 실험 유형별 기본 템플릿을 제공합니다.
  - CCK-8 2-fold dilution
  - MTT dose-response
  - ELISA standard curve
  - Drug screening duplicate layout
  - Custom blank template
- 기존 실험을 복제해 새 실험을 만들 수 있습니다.
- 그룹, 색상, 농도 패턴을 템플릿으로 재사용합니다.

### 3.9 검색, 태그, 필터

- 실험 제목, 메모, 프로젝트, compound, cell line, 태그로 검색합니다.
- 날짜, 실험 유형, 상태, 프로젝트별 필터를 제공합니다.
- 추천 태그를 제공합니다.
  - CCK8
  - MTT
  - ELISA
  - DoseResponse
  - Toxicity
  - CellViability
  - DrugScreening

### 3.10 내보내기와 공유

- PDF 리포트를 생성합니다.
- plate layout 이미지를 PNG로 내보냅니다.
- raw data와 분석 결과를 CSV로 내보냅니다.
- Excel 형식 내보내기를 지원합니다.
- JSON 백업과 복원을 지원합니다.
- 공유 sheet를 통해 AirDrop, Mail, Files, KakaoTalk 등 iOS 공유 기능을 사용할 수 있게 합니다.

### 3.11 실수 방지와 검증

- 저장 또는 실험 시작 전 layout 검증을 수행합니다.
- 검증 항목은 다음을 포함합니다.
  - 빈 well 확인
  - control 없음 경고
  - blank 없음 경고
  - replicate 수 부족 경고
  - 농도 단위 혼용 경고
  - 같은 well 중복 지정 방지
  - edge well 사용 여부 표시
  - plate 방향 A1 표시
  - 결과 파일과 layout 간 well 좌표 불일치 경고
- 경고는 blocking error와 non-blocking warning으로 구분합니다.

### 3.12 동기화와 백업

- 1차 버전은 로컬 우선으로 동작합니다.
- 2차 버전에서 Supabase 또는 Firebase 기반 계정 동기화를 검토합니다.
- 개인 연구 데이터 보호를 위해 사용자가 명시적으로 켠 경우에만 클라우드 동기화를 수행합니다.
- JSON export/import를 통한 수동 백업을 제공합니다.

## 4. 비기능 요구사항

- 모바일 실험 환경에서 빠르게 사용할 수 있어야 합니다.
- 오프라인에서도 실험 생성, 편집, 사진 첨부가 가능해야 합니다.
- 96개 well을 부드럽게 렌더링해야 합니다.
- 실험 데이터는 로컬 DB에 안정적으로 저장해야 합니다.
- 농도와 부피 계산 로직은 단위 테스트로 검증해야 합니다.
- UI는 간결하고 메모앱처럼 부담 없는 톤을 유지합니다.
- 연구 데이터 보호를 위해 민감한 데이터 업로드 여부를 사용자가 제어할 수 있어야 합니다.

## 5. Flutter 기술 스택 권장안

### 5.1 기본 스택

- Framework: Flutter stable
- Language: Dart
- State management: Riverpod
- Local database: Drift 또는 Isar
- Navigation: GoRouter
- Immutable model/codegen: Freezed, json_serializable
- Chart: fl_chart
- File picker/import: file_picker
- Photo picker: image_picker 또는 photo_manager
- PDF export: pdf, printing
- CSV parsing/export: csv
- Excel import/export: excel
- Local secure settings: flutter_secure_storage
- Path/file storage: path_provider

### 5.2 추천 아키텍처

Clean Architecture를 과하게 적용하기보다, 기능 단위 modular architecture를 권장합니다.

```text
lib/
  app/
    app.dart
    router.dart
    theme.dart
  core/
    database/
    errors/
    utils/
    units/
  features/
    experiments/
    plates/
    dilution/
    pipetting/
    attachments/
    imports/
    analysis/
    export/
    templates/
  shared/
    widgets/
    models/
```

각 feature는 `data`, `domain`, `presentation` 하위 구조를 가집니다.

```text
features/plates/
  data/
  domain/
  presentation/
```

### 5.3 데이터 저장 전략

- 초기 개발 속도와 쿼리 안정성을 고려하면 Drift를 우선 검토합니다.
- 객체 중심 개발 경험을 더 중시하면 Isar를 검토합니다.
- 첨부 파일은 DB에 직접 넣지 않고 앱 문서 디렉터리에 저장한 뒤 DB에는 경로와 메타데이터만 저장합니다.
- 분석 결과는 재계산 가능하도록 raw data와 analysis config를 보존합니다.

## 6. 데이터 모델 초안

### 6.1 Experiment

```text
Experiment
- id
- title
- projectName
- experimentType
- researcher
- status
- createdAt
- updatedAt
- performedAt
- notes
- tags
```

### 6.2 Plate

```text
Plate
- id
- experimentId
- name
- plateType
- rowCount
- columnCount
- orientation
- notes
```

### 6.3 Well

```text
Well
- id
- plateId
- rowIndex
- columnIndex
- rowLabel
- columnLabel
- groupId
- role
- concentrationValue
- concentrationUnit
- volumeValue
- volumeUnit
- replicateIndex
- note
- resultValue
- resultUnit
- excluded
```

### 6.4 WellGroup

```text
WellGroup
- id
- plateId
- name
- shortLabel
- color
- compoundName
- role
- concentrationUnit
- dilutionFactor
- startConcentration
- direction
- replicateCount
- notes
```

### 6.5 Attachment

```text
Attachment
- id
- experimentId
- plateId
- wellId
- type
- filePath
- fileName
- caption
- createdAt
```

### 6.6 AnalysisResult

```text
AnalysisResult
- id
- plateId
- analysisType
- configJson
- resultJson
- createdAt
```

### 6.7 Template

```text
Template
- id
- name
- experimentType
- plateType
- layoutJson
- createdAt
- updatedAt
```

## 7. 화면 설계

### 7.1 Home

- 검색창
- 최근 실험 목록
- 폴더 또는 프로젝트 목록
- 실험 유형 필터
- 새 실험 버튼

### 7.2 Experiment Detail

- 제목, 날짜, 프로젝트, 실험 유형
- plate preview card
- 메모 섹션
- 사진/파일 첨부 섹션
- 결과/분석 섹션
- export/share 버튼

### 7.3 Plate Editor

- 상단 toolbar
  - 선택 모드
  - 그룹 지정
  - 농도 계산
  - 복사/붙여넣기
  - 검증
- 중앙 96-well plate grid
- 하단 bottom sheet
  - 선택 well 상세
  - 선택 그룹 상세
  - 농도 리스트
  - 경고 목록

### 7.4 Dilution Builder

- 시작 농도
- 단위
- 희석 배수
- 방향
- 단계 수
- 반복 수
- control 추가 옵션
- 미리보기
- 적용 버튼

### 7.5 Pipetting Plan

- 계산 조건 요약
- 단계별 체크리스트
- well별 필요량 표
- master mix 요약

### 7.6 Analysis

- 데이터 import
- plate reader 값 preview
- normalization 설정
- replicate 통계
- curve fitting 결과
- 그래프와 표

### 7.7 Templates

- 기본 템플릿 목록
- 사용자 템플릿 목록
- 템플릿 미리보기
- 템플릿 적용

## 8. 개발 마일스톤

### Phase 0: 프로젝트 기반 구축

목표: Flutter 앱의 기본 구조와 개발 규칙을 정합니다.

작업:
- Flutter 프로젝트 생성
- lint 설정
- Riverpod, GoRouter, DB 패키지 설정
- 앱 테마와 기본 navigation 구축
- CI에서 format, analyze, test 실행
- 기본 모델과 repository 인터페이스 정의

완료 기준:
- 빈 앱이 iOS simulator와 Android emulator에서 실행됩니다.
- `flutter analyze`와 `flutter test`가 통과합니다.

### Phase 1: 실험 노트 MVP

목표: 메모앱처럼 실험을 생성하고 관리합니다.

작업:
- Experiment CRUD
- Home list/search UI
- Experiment detail UI
- 로컬 DB 저장
- 태그와 상태 관리

완료 기준:
- 앱을 껐다 켜도 실험 노트가 유지됩니다.
- 제목, 날짜, 실험 유형, 메모를 수정할 수 있습니다.

### Phase 2: 96-well plate editor

목표: plate layout을 시각적으로 만들고 편집합니다.

작업:
- 8x12 grid 렌더링
- well 좌표 A1-H12 표시
- 단일/범위/행/열 선택
- 그룹 생성과 색상 지정
- bottom sheet 상세 정보
- well 정보 저장

완료 기준:
- 사용자가 드래그로 범위를 선택하고 실험군을 지정할 수 있습니다.
- 저장된 plate layout이 다시 열렸을 때 복원됩니다.

### Phase 3: 농도와 serial dilution

목표: 사진과 같은 2배 희석 농도 배치를 자동 생성합니다.

작업:
- Dilution domain service 구현
- 시작 농도, 희석 배수, 방향, 단계 수 입력 UI
- 미리보기와 적용
- 단위 관리
- 수동 override
- 단위 테스트 작성

완료 기준:
- `1000, 500, 250, 125, 62.5, 31.25, 0` 같은 농도 series를 정확히 생성합니다.
- 가로/세로 방향과 replicate 적용이 동작합니다.

### Phase 4: 사진/파일 첨부와 export 기본

목표: 실험 기록을 노트처럼 풍부하게 남깁니다.

작업:
- 사진 첨부
- 파일 첨부
- 첨부 파일 metadata 저장
- plate layout PNG export
- CSV export
- PDF report 초안

완료 기준:
- 실험 상세에서 사진을 첨부하고 다시 볼 수 있습니다.
- plate layout과 기본 실험 정보를 외부 파일로 공유할 수 있습니다.

### Phase 5: 템플릿과 실수 방지

목표: 반복 실험을 빠르게 만들고 실수를 줄입니다.

작업:
- 템플릿 저장/불러오기
- 기본 템플릿 제공
- layout validation service 구현
- control/blank/replicate 경고
- edge well 표시

완료 기준:
- 기존 plate layout을 템플릿으로 저장하고 새 실험에 적용할 수 있습니다.
- 저장 전 주요 경고를 보여줍니다.

### Phase 6: pipetting plan

목표: 실험 준비와 처리 과정을 체크리스트화합니다.

작업:
- stock/final concentration 계산
- well별 필요 stock/diluent volume 계산
- master mix 계산
- overage 설정
- checklist UI
- PDF/CSV export 연동

완료 기준:
- 사용자가 final volume과 stock concentration을 입력하면 필요한 부피와 단계별 plan을 확인할 수 있습니다.

### Phase 7: 결과 import와 분석

목표: 실험 후 결과 데이터를 plate layout과 연결합니다.

작업:
- CSV import
- Excel import
- well coordinate mapping
- raw data preview
- blank correction
- control normalization
- replicate 평균/표준편차/CV
- chart UI

완료 기준:
- plate reader 결과를 가져와 well에 매핑하고 기본 통계를 볼 수 있습니다.

### Phase 8: 고급 분석과 동기화

목표: 장기적으로 연구 노트와 분석 플랫폼으로 확장합니다.

작업:
- dose-response curve fitting
- IC50 계산
- outlier 표시
- JSON 백업/복원
- Supabase/Firebase 동기화 PoC
- 사용자 계정과 데이터 보안 정책 설계

완료 기준:
- dose-response 실험 결과를 그래프로 보고 IC50를 계산할 수 있습니다.
- 사용자가 명시적으로 선택한 경우에만 클라우드 백업을 사용할 수 있습니다.

## 9. 우선순위

### P0: 반드시 필요한 기능

- 실험 노트 CRUD
- 96-well plate editor
- well 드래그 선택
- 실험군 색상/라벨 지정
- 농도 입력
- serial dilution 자동 계산
- 로컬 저장

### P1: 빠르게 추가해야 하는 기능

- 사진 첨부
- 템플릿 저장/불러오기
- control/blank/replicate 태그
- layout validation
- CSV/PDF export
- pipetting plan 기본

### P2: 고급 기능

- plate reader CSV/Excel import
- blank 보정과 normalization
- 평균/표준편차 계산
- 그래프
- JSON 백업/복원

### P3: 장기 기능

- IC50 계산
- OCR 또는 plate 이미지 인식
- 클라우드 동기화
- 협업
- audit trail

## 10. 테스트 전략

### 10.1 Unit test

- serial dilution 계산
- 단위 변환
- volume 계산
- master mix 계산
- layout validation
- CSV parsing
- normalization

### 10.2 Widget test

- 실험 생성 form
- plate grid selection
- dilution builder preview
- bottom sheet editing
- attachment list

### 10.3 Integration test

- 새 실험 생성부터 plate 저장까지의 플로우
- 템플릿 적용 플로우
- CSV import 후 분석 플로우
- export 플로우

### 10.4 수동 QA

- iPhone 작은 화면에서 plate 조작성 확인
- iPad landscape에서 plate 조작성 확인
- 실험 장갑 착용 환경을 고려한 터치 영역 확인
- 오프라인 상태에서 저장 확인

## 11. 주요 기술 리스크와 대응

### 11.1 작은 화면에서 96개 well 조작이 어려움

대응:
- pinch zoom 또는 segmented zoom을 제공합니다.
- 행/열 헤더 선택을 제공합니다.
- bottom sheet로 상세 편집을 분리합니다.
- well 내부 텍스트는 최소화합니다.

### 11.2 농도/부피 계산 실수

대응:
- 계산 로직을 UI와 분리해 domain service로 구현합니다.
- 단위 테스트를 충분히 작성합니다.
- 적용 전 미리보기를 제공합니다.
- 수동 수정 이력을 남깁니다.

### 11.3 plate reader 데이터 형식 다양성

대응:
- 초기에는 CSV template을 정합니다.
- import mapping UI를 제공합니다.
- 파일 파서는 adapter 구조로 확장합니다.

### 11.4 연구 데이터 보안

대응:
- 로컬 우선 저장을 기본값으로 합니다.
- 클라우드 동기화는 opt-in으로 제공합니다.
- export 파일은 사용자가 명시적으로 공유할 때만 생성합니다.

## 12. 초기 개발 체크리스트

- [ ] Flutter 프로젝트 생성
- [ ] 앱 이름과 bundle id 확정
- [ ] iOS/Android 최소 지원 버전 결정
- [ ] 디자인 톤 결정: iOS Notes 스타일, light mode 우선
- [ ] DB 패키지 선택: Drift vs Isar
- [ ] 라우팅과 상태관리 세팅
- [ ] Experiment 모델 구현
- [ ] Plate/Well/Group 모델 구현
- [ ] DilutionService 구현
- [ ] 96-well grid prototype 구현
- [ ] MVP 사용자 테스트 진행

## 13. 추천 개발 순서 요약

1. Flutter 앱 뼈대를 만듭니다.
2. 실험 노트 CRUD를 먼저 완성합니다.
3. 96-well plate grid를 구현합니다.
4. 드래그 선택과 그룹 색상 지정을 붙입니다.
5. serial dilution 계산기를 구현합니다.
6. 사진 첨부와 템플릿 저장을 추가합니다.
7. pipetting plan과 validation을 추가합니다.
8. 결과 import와 분석 기능을 단계적으로 확장합니다.

## 14. MVP 완료 정의

MVP는 다음 플로우가 자연스럽게 동작하면 완료로 봅니다.

1. 앱을 열고 새 실험을 생성합니다.
2. 실험 유형으로 CCK-8 또는 custom을 선택합니다.
3. 96-well plate를 추가합니다.
4. A1:B7 범위를 드래그 선택합니다.
5. Drug A 그룹을 보라색으로 지정합니다.
6. 시작 농도 1000, 희석 배수 2, 아래 방향, 마지막 control 0을 적용합니다.
7. plate에 `1000, 500, 250, 125, 62.5, 31.25, 0`이 표시됩니다.
8. 실험 메모와 plate 사진을 첨부합니다.
9. 앱을 재실행해도 데이터가 유지됩니다.
10. plate layout을 CSV 또는 PDF로 내보냅니다.
