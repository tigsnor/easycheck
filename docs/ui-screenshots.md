# PlateNote UI 확인 가이드

GitHub PR 화면에서는 PNG 같은 바이너리 파일 diff가 `Binary file not shown` 또는 `바이너리 파일 지원되지 않음`으로 표시됩니다. 따라서 저장소에는 스크린샷 이미지를 커밋하지 않고, UI를 보고 싶을 때 로컬에서 앱을 실행해 직접 확인하는 방식으로 관리합니다.

## 확인할 주요 화면

1. **실험 노트 홈**
   - 최근 실험 목록, 검색창, `새 실험`, `빠른 시작` 카드가 보이는지 확인합니다.
2. **실험 상세/노트**
   - 실험 제목, 실험 유형, 상태, 프로젝트, 메모 입력 영역, `96-well Plate 열기` 버튼을 확인합니다.
3. **96-well Plate Editor**
   - A-H/1-12 plate grid, 기본 희석 농도, 선택 영역 카드, well 상세 카드가 보이는지 확인합니다.
4. **Plate 실험군/농도 요약**
   - plate grid 아래에서 실험군별 색상, well 수, 역할, 농도 series가 표시되는지 확인합니다.
5. **희석 계산 Builder**
   - `희석 계산 적용`을 눌러 시작 농도, 희석 배수, 단계 수, 반복 well 수, 방향, 0 농도 control 포함 여부를 입력할 수 있는지 확인합니다.
6. **Plate 결과 일괄 입력**
   - `결과 일괄 입력`에서 Excel/Plate reader 행렬 붙여넣기, 좌표 미리보기, 오류와 덮어쓰기 안내가 표시되는지 확인합니다.
7. **전체 데이터 백업 · 복원**
   - 실험 홈의 백업 버튼에서 JSON 복사·파일 공유, Files 파일 선택, 복원 미리보기, 병합 확인 화면을 확인합니다.

## 로컬에서 직접 UI 보는 방법

```bash
scripts/bootstrap_flutter.sh
export PATH="$PWD/.tool/flutter/bin:$PATH"
flutter pub get
flutter run
```

시뮬레이터나 연결된 기기에서 위 화면들을 순서대로 확인하면 됩니다.

## 임시 스크린샷을 남기고 싶을 때

PR에 이미지를 커밋하지 말고, 로컬에서 임시로 캡처한 뒤 이슈/PR 코멘트에 첨부하는 방식을 권장합니다.

- macOS iOS Simulator: `Cmd + S`
- Android Emulator: 오른쪽 툴바의 Screenshot 버튼
- Flutter CLI/VM Service 환경: 필요 시 `flutter screenshot` 사용

## 왜 golden test를 제거했나?

현재 단계에서는 사용자가 한 번 확인할 UI 이미지가 필요할 뿐, 픽셀 단위 회귀 검증까지는 필요하지 않습니다. Golden test는 이미지 파일을 저장소에 포함해야 해서 PR 리뷰 경험을 해치고, 폰트/렌더링 환경 차이로 불필요한 실패를 만들 수 있습니다. 그래서 자동 스크린샷 생성/검증은 제거하고 일반 widget/unit test만 유지합니다.
