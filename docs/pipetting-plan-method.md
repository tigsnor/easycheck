# PlateNote 피펫팅 계획 계산 기준

PlateNote는 각 목표 농도의 master mix를 하나의 stock에서 만드는 **직접 희석**과, 높은 농도에서 낮은 농도로 순서대로 옮기는 **연속 희석** 계획을 제공합니다.

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

## 연속 희석과 단계별 잔여량

연속 희석은 마지막 양성 농도부터 역순으로 계산하여, 각 농도에서 Plate에 분주할 master mix를 남긴 뒤에도 다음 농도를 만들 수 있게 준비량을 확보합니다.

- 각 단계의 `Plate 분주량`은 well당 부피 × 반복 수 × 여유분입니다.
- 다음 단계에 필요한 전체 부피를 기준으로 C1V1 = C2V2를 적용해 transfer 부피를 계산합니다.
- 현재 단계의 총 준비량은 Plate 분주량과 다음 단계 transfer 부피의 합입니다.
- 0 농도 control은 이전 농도 용액을 옮기지 않고 희석액만 별도로 준비합니다.
- 연속 희석은 목표 농도가 높은 농도에서 낮은 농도 순서일 때만 계산합니다.

## 실험 전 확인사항

- 1 µL 미만의 stock 분주가 계산되면 앱에서 경고합니다. 사용하는 피펫의 검증 범위를 확인하고 필요하면 중간 희석액을 준비해야 합니다.
- 앱은 stock과 목표 농도의 단위 환산을 자동으로 수행하지 않습니다. 두 값에 동일한 단위를 사용해야 합니다.
- 계산값은 제조 계획 보조용입니다. 실제 실험에서는 용액 밀도, 용매 허용 농도, dead volume, 장비 정확도와 연구실 SOP를 함께 확인해야 합니다.
- 연속 희석 중 혼합 손실, tube dead volume과 tip 내 잔류량은 자동 보정하지 않으므로 연구실 SOP에 따라 추가 여유분을 설정해야 합니다.
