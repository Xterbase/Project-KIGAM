# LumiGuide

루미네선스(OSL/TL) 연대 해석 워크플로 보조 도구.

원시 측정 데이터에서 연대 계산까지의 분석 과정을 한곳에 모아 시각화하고, 등가선량(De)
분포의 특성(과분산·왜도·다봉성)을 근거로 통계 연대모델(CAM / MAM / FMM 등) 선택을 돕는다.
통계 계산은 R [`Luminescence`](https://cran.r-project.org/package=Luminescence) 패키지가
담당하며, 이 프로젝트는 그 통계를 재구현하지 않는다.

## 현재 단계

**웹 애플리케이션으로 재구성하는 중이다.** Streamlit으로 만든 첫 버전(ver.1.0)은
`version1_streamlit/`에 참고용으로 보존하고, 분석 계층(`R/Analysis.R`)을 먼저 다진 뒤
서버 기반 웹 애플리케이션으로 옮긴다.

```
원시 데이터 → 신호 분석 → De 분포 분석 → 모델 추천 → 통계모델 적용 → 연대 계산 → 결과·보고서
```

| 구성 | 위치 | 상태 |
|---|---|---|
| 분석 계층 | `R/Analysis.R` | 업로드 검사, 신호 곡선, SAR(De·QC 분류), De 분포 분석 구현. 보강 중 |
| ver.1.0 UI | `version1_streamlit/` | 동작하지만 더 이상 확장하지 않음 |
| 웹 애플리케이션 | — | 설계 단계 |

## 설계 원칙

- **모델 선택은 결정적(deterministic)이다.** 같은 입력과 같은 임계값이면 항상 같은
  모델을 낸다. 연대값이 출판되려면 재현 가능해야 하기 때문이다. 모델은 문헌 기반 규칙이
  고르고, 언어 모델은 그 선택의 근거를 문헌과 함께 설명하는 역할에 머문다.
- **분류하되 조용히 버리지 않는다.** 품질검사에서 탈락한 aliquot도 판정 근거와 함께
  보관한다. 자동 제외는 결과를 바꾸면서 기록을 남기지 않는 판단이 되기 때문이다.
- **결과를 바꾸는 파라미터는 결과에 함께 기록한다.** 예: signal/background integral은
  De를 크게 바꾸지만 측정 파일에는 남지 않으므로 모든 SAR 결과 행에 찍는다.

## 알려진 한계

- **single-grain(한 POSITION에 여러 GRAIN) 파일은 차단된다.** 조용히 틀린 곡선을 그리는
  것을 막은 상태이며, 지원하는 것이 아니다. 가장 먼저 풀 과제다.
- **De는 현재 초(s) 단위다.** 선원 선량률(Gy/s)을 적용해야 Gy가 된다. ver.1.0 화면의
  "Gy" 표기는 틀렸다.
- **다봉 데이터의 MAM/FMM 구분을 아직 신뢰하지 말 것.** 추천 규칙이 양의 왜도 게이트를
  다봉 게이트보다 먼저 평가해, 실제 다성분 혼합이 MAM으로 분류될 수 있다. 출판되는
  연대값에 영향을 주므로 전문가 검토 후에 고친다.
- **음수/0 De는 지원하지 않는다.** 로그 기반 모델을 적용할 수 없어 명시적으로 중단한다.

## 요구 사항

- R + `Luminescence` 패키지
- Python 3.14 (ver.1.0 앱과 셀프 체크용, 프로젝트 자체 virtualenv)

```r
install.packages("Luminescence")
```

```bash
python3 -m venv venv && source venv/bin/activate
pip install -r requirements.txt   # pandas, rpy2, streamlit
```

## 검증

테스트 프레임워크 대신 각 모듈의 `__main__`에 `assert` 기반 셀프 체크가 있다.
`r_runner.py`의 셀프 체크가 `R/Analysis.R`을 Luminescence 내장 예제 데이터
(`CWOSL.SAR.Data`)로 실행해 검증하므로, 저장소에 측정 데이터가 필요 없다.

```bash
venv/bin/python version1_streamlit/utils/r_runner.py        # R 설치 필요, 약 2초
venv/bin/python version1_streamlit/utils/model_recommend.py
venv/bin/python version1_streamlit/utils/file_utils.py
```

ver.1.0 화면을 직접 보려면:

```bash
streamlit run version1_streamlit/main.py
```

측정 데이터(`*.bin`, `*.rda` 등)는 저장소에 커밋하지 않는다.
