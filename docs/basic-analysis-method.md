# EasyCheck 기본 결과 분석 계산 기준

EasyCheck의 기본 분석은 입력된 raw 측정값을 빠르게 확인하기 위한 보조 계산입니다. 원본 측정값은 변경하지 않으며, 자동 이상치 제거·통계적 유의성 검정·IC50 계산은 수행하지 않습니다.

## 반복 측정 묶음

다음 값이 모두 같은 well을 하나의 반복 측정 series로 묶습니다.

- 실험군
- 농도와 농도 단위
- 결과 단위

`분석에서 제외`가 켜진 well은 통계 계산에서 제외하고 well 번호와 제외 개수만 표시합니다.

## 평균

포함된 측정값의 산술 평균을 사용합니다.

`mean = sum(x) / n`

## 표준편차

반복 측정이 두 개 이상인 경우 표본 표준편차를 사용합니다.

`SD = sqrt(sum((x - mean)^2) / (n - 1))`

측정값이 한 개뿐이면 SD를 계산하지 않습니다.

## CV

CV는 raw 평균과 표본 표준편차로 계산합니다.

`CV(%) = abs(SD / raw mean) × 100`

raw 평균이 0이거나 SD를 계산할 수 없으면 CV도 표시하지 않습니다.

## Blank 보정

같은 결과 단위에 속한, 분석에서 제외되지 않은 모든 blank well의 평균을 사용합니다.

`blank corrected mean = raw mean - blank mean`

같은 결과 단위의 blank가 없으면 blank 평균을 0으로 두어 raw 평균과 같은 값을 표시하고, 화면에 기준이 없음을 안내합니다.

## Control 정규화

같은 결과 단위에서 다음 순서로 실제 존재하는 첫 control 역할을 하나만 선택합니다.

1. Vehicle control
2. Untreated control
3. Negative control

여러 역할을 섞어 평균하지 않습니다. 선택된 control도 blank 보정한 평균을 사용합니다.

`normalized(%) = series blank-corrected mean / control blank-corrected mean × 100`

control이 없거나 blank 보정 control 평균이 0이면 정규화 비율을 계산하지 않습니다.

## 해석 시 주의사항

- 계산 결과는 입력값과 well 역할 설정의 정확성에 의존합니다.
- 서로 다른 결과 단위는 절대 합치지 않습니다.
- Positive control은 baseline normalization 기준으로 자동 사용하지 않습니다.
- 자동 outlier 판정이나 제외는 하지 않습니다.
- 실제 보고서나 논문 분석 전에는 연구실의 검증된 분석 절차와 별도 소프트웨어로 다시 확인해야 합니다.
