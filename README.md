# easycheck

EasyCheck는 생명과학 연구원이 96-well plate 실험 설계, 농도 계산, 실험 노트, 결과 관리를 모바일에서 수행할 수 있도록 만드는 Flutter 앱 프로젝트입니다.

## 문서

- [Flutter 개발 플랜](docs/flutter-development-plan.md)

## 현재 구현 상태

첫 구현 단계로 Flutter 앱의 기본 골격과 96-well plate 화면 프로토타입을 추가했습니다.

- Flutter 앱 진입점과 iOS 메모앱 느낌의 기본 테마
- 96-well plate grid 프로토타입
- 선택한 well의 상세 정보를 보여주는 카드
- `1000 → 500 → 250 → 125 → 62.5 → 31.25 → 0` 형태의 2배 희석 계산 서비스
- 실험, plate, well, well group 도메인 모델 초안

## 로컬 실행

Flutter SDK가 설치된 환경에서 아래 명령을 실행합니다.

```bash
flutter pub get
flutter run
```

## 테스트

```bash
flutter test
```
