# EasyCheck 수동 QA 체크리스트

이 문서는 개발자 테스트 가능도를 100%에 가깝게 만들기 위한 기본 수동 검증 절차입니다.

## 사전 준비

```bash
scripts/bootstrap_flutter.sh
export PATH="$PWD/.tool/flutter/bin:$PATH"
flutter pub get
flutter devices
flutter run
```

## 0. 실제 기기/시뮬레이터 실행 확인

- [ ] `flutter devices`에서 iPhone Simulator, Android Emulator 또는 실제 기기가 표시된다.
- [ ] `flutter run -d <device-id>`로 앱이 실행된다.
- [ ] 앱을 종료 후 다시 실행해도 첫 화면이 정상 표시된다.

## 1. 실험 노트 기본 흐름

- [ ] 앱이 실행되고 `실험 노트` 홈 화면이 보인다.
- [ ] `새 실험` 또는 `첫 실험 만들기`를 눌러 bottom sheet가 열린다.
- [ ] 제목, 실험 유형, 프로젝트, 메모를 입력하고 생성한다.
- [ ] 생성된 실험이 최근 실험 목록에 표시된다.
- [ ] 검색창에서 제목 또는 태그로 검색했을 때 결과가 필터링된다.
- [ ] 실험 카드를 눌러 상세 화면으로 이동한다.
- [ ] 제목/상태/메모를 수정하고 저장한다.
- [ ] 앱을 재시작해도 실험 노트가 유지된다.

## 2. Plate 기본 흐름

- [ ] 실험 카드 또는 상세 화면에서 `Plate 열기`를 눌러 plate editor로 이동한다.
- [ ] 96-well plate와 A-H/1-12 헤더가 보인다.
- [ ] 기본 A/B열에 `1000 → 500 → 250 → 125 → 62.5 → 31.25 → 0` 패턴이 보인다.
- [ ] `희석 계산 적용`에서 시작 농도, 희석 배수, 단계 수, 반복 well 수, 방향을 바꿔 plate에 적용한다.
- [ ] 단일 well을 탭하면 상세 카드가 해당 well로 바뀐다.
- [ ] 행 헤더 `A`를 탭하면 12개 well이 선택된다.
- [ ] 열 헤더 `1`을 탭하면 8개 well이 선택된다.
- [ ] `범위 시작` 후 다른 well을 탭하면 사각형 범위가 선택된다.
- [ ] 선택 영역에 `그룹 지정`을 눌러 그룹명, 라벨, 색상, 역할, 단위를 입력한다.
- [ ] 지정한 그룹 색상과 라벨이 plate에 표시된다.
- [ ] 선택한 well의 농도를 편집하고 저장한다.
- [ ] `Plate 내보내기`를 열고 TSV 텍스트가 표시되며 `복사하기`를 누를 수 있다.
- [ ] 앱을 재시작해도 plate layout과 그룹 정보가 유지된다.

## 3. UI 직접 확인

- [ ] [UI 확인 가이드](ui-screenshots.md)를 보고 실험 노트 홈, 실험 상세, plate editor, plate 요약, 희석 계산 Builder 화면을 직접 확인한다.
- [ ] 필요한 경우 로컬에서 임시 스크린샷을 캡처해 PR 코멘트나 이슈에 첨부한다. 이미지 파일은 저장소에 커밋하지 않는다.

## 4. 자동 검증

```bash
dart format --set-exit-if-changed .
flutter analyze
flutter test
```

모든 명령이 통과해야 다음 기능 개발로 넘어갑니다.
