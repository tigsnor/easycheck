# EasyCheck 피펫팅 계획 계산 기준

EasyCheck의 첫 피펫팅 계획은 각 목표 농도의 master mix를 하나의 stock에서 **직접 희석**하는 방식입니다. 단계 간 용액을 옮기는 serial transfer 방식은 아직 계산하지 않습니다.

## 입력값

- Stock 농도
- 목표 농도 series
- Well당 최종 부피
- 반복 well 수
- 여유분 비율
- 농도 단위 (stock과 목표 농도가 공유)

Plate 분주 부피는 현재 µL 기준으로 계산하고 저장합니다.

Stock 농도와 목표 농도는 같은 농도 단위를 사용해야 합니다. 목표 농도는 stock 농도보다 높을 수 없습니다.

## Master mix 총량

각 농도별 준비량은 다음과 같이 계산합니다.

`total volume = volume per well × replicate count × (1 + overage percent / 100)`

예를 들어 well당 100 µL, 2반복, 여유분 10%이면 각 농도별로 220 µL를 준비합니다.

## Stock과 희석액

C1V1 = C2V2 관계를 사용합니다.

`stock volume = total volume × target concentration / stock concentration`

`diluent volume = total volume - stock volume`

0 농도 control은 stock 0, 희석액 전체 부피로 표시합니다.

## 실험 전 확인사항

- 1 µL 미만의 stock 분주가 계산되면 앱에서 경고합니다. 사용하는 피펫의 검증 범위를 확인하고 필요하면 중간 희석액을 준비해야 합니다.
- 앱은 stock과 목표 농도의 단위 환산을 자동으로 수행하지 않습니다. 두 값에 동일한 단위를 사용해야 합니다.
- 계산값은 제조 계획 보조용입니다. 실제 실험에서는 용액 밀도, 용매 허용 농도, dead volume, 장비 정확도와 연구실 SOP를 함께 확인해야 합니다.
- 현재 버전은 serial transfer 과정과 단계별 잔여량을 계산하지 않습니다.
