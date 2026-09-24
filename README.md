# Luminous

> 가칭. 2026-09-24에 LumiGuide에서 이름을 바꿨으며, 최종 이름은 정해지지 않았다.

루미네선스(OSL/TL) 연대 해석 워크플로 보조 도구.

원시 측정 데이터에서 연대 계산까지의 분석 과정을 한곳에 모아 시각화하고, 등가선량(De)
분포의 특성(과분산·왜도·다봉성)을 근거로 통계 연대모델(CAM / MAM / FMM 등) 선택을 돕는다.
통계 계산은 R [`Luminescence`](https://cran.r-project.org/package=Luminescence) 패키지가
담당하며, 이 프로젝트는 그 통계를 재구현하지 않는다.

## 현재 단계

**웹 애플리케이션으로 재구성하는 중이다.** Streamlit으로 만든 첫 버전(ver.1.0)은
`version1_streamlit/`에 참고용으로 보존하고, 분석 계층(`R/`)을 먼저 다진 뒤 서버 기반 웹
애플리케이션으로 옮긴다. 웹 구조는 브라우저 → PHP → `Rscript R/run.R` → 분석 계층이며,
R은 그래프를 그림이 아니라 데이터(JSON)로 넘기고 브라우저가 그린다.

```
원시 데이터 → 신호 분석 → De 분포 분석 → 모델 추천 → 통계모델 적용 → 연대 계산 → 결과·보고서
```

| 구성 | 위치 | 상태 |
|---|---|---|
| ① 로드 | `R/01_load.R` | BIN/RDA 읽기, single-grain·single-aliquot 자동 판별 |
| ② 신호 | `R/02_signal.R` | POSITION(+GRAIN)별 record, 신호 곡선 데이터 |
| ③ SAR | `R/03_sar.R` | 분석 단위별 De·QC 분류, single-grain / single-aliquot 모드, 진행률 파일 |
| ④ 분포 진단 | `R/04_distribution.R` | 과분산·왜도·FMM BIC, 방사형 그래프 좌표 |
| ⑤ 연령 모델 | `R/05_models.R` | 규칙 기반 추천 → CAM/MAM/FMM 적용 (초안, 연구자 검토 대기) |
| ⑥ 선량률·연령 | — | 선원 선량률을 받은 뒤 구현 |
| 웹 진입점 | `R/run.R` | JSON 입력 → 동작 → JSON 출력 (PHP와 R 사이의 약속) |
| 분석 계층 진입 | `R/Analysis.R` | 위 단계 파일을 순서대로 불러온다 |
| ver.1.0 UI | `version1_streamlit/` | 동작하지만 더 이상 확장하지 않음 |
| 웹 화면(PHP) | — | 설계 단계 |

## 설계 원칙

- **모델 선택은 결정적(deterministic)이다.** 같은 입력과 같은 임계값이면 항상 같은
  모델을 낸다. 연대값이 출판되려면 재현 가능해야 하기 때문이다. 모델은 문헌 기반 규칙이
  고르고, 언어 모델은 그 선택의 근거를 문헌과 함께 설명하는 역할에 머문다.
- **분류하되 조용히 버리지 않는다.** 품질검사에서 탈락한 aliquot도 판정 근거와 함께
  보관한다. 자동 제외는 결과를 바꾸면서 기록을 남기지 않는 판단이 되기 때문이다.
- **결과를 바꾸는 파라미터는 결과에 함께 기록한다.** 예: signal/background integral은
  De를 크게 바꾸지만 측정 파일에는 남지 않으므로 모든 SAR 결과 행에 찍는다. 측정 모드,
  난수 시드, sigmab, 사용한 패키지 이름과 버전도 같은 이유로 결과에 남긴다.
- **같은 입력이면 같은 결과다.** Luminescence는 De 오차를 무작위 시뮬레이션으로 추정하므로
  분석 단위마다 시드를 고정한다. 고정하지 않으면 경계의 grain이 실행마다 QC를 통과했다
  탈락했다 한다.

## 알려진 한계

- **분석 결과는 아직 독립 기준과 비교 검증되지 않았다.** 셀프 체크는 현재 코드의 출력을
  고정해 회귀를 막을 뿐이다. 연구자의 기존 분석 결과와 grain 단위로 비교하는 것이 다음
  검증이다.
- **판단 파라미터가 확정되지 않았다.** QC 기준은 Luminescence 기본값이고, 모델 추천에
  필요한 최소 De 개수, single-aliquot용 sigmab, FMM 성분 선택 기준은 연구자 검토를
  기다린다.
- **De는 현재 초(s) 단위다.** 선원 선량률(Gy/s)을 적용해야 Gy가 된다. ver.1.0 화면의
  "Gy" 표기는 틀렸다.
- **다봉 데이터의 MAM/FMM 구분을 아직 신뢰하지 말 것.** 추천 규칙이 양의 왜도 게이트를
  다봉 게이트보다 먼저 평가해, 실제 다성분 혼합이 MAM으로 분류될 수 있다. 출판되는
  연대값에 영향을 주므로 전문가 검토 후에 고친다.
- **음수/0 De는 지원하지 않는다.** 로그 기반 모델을 적용할 수 없어 명시적으로 중단한다.

## 요구 사항

- R + `Luminescence` 패키지 (`jsonlite`는 Luminescence와 함께 설치된다)
- Python 3.14 (ver.1.0 앱과 그 셀프 체크용, 프로젝트 자체 virtualenv)

```r
install.packages("Luminescence")
```

```bash
python3 -m venv venv && source venv/bin/activate
pip install -r requirements.txt   # pandas, rpy2, streamlit
```

## 검증

테스트 프레임워크 대신 `assert` 기반 셀프 체크가 있다. 분석 계층은 웹과 같은 방식
(`Rscript`)으로 점검하며, Luminescence 내장 예제 데이터로 fixture를 만들므로 저장소에 측정
데이터가 필요 없다. 로컬에 single-grain 테스트 파일(`test_data/`, 커밋하지 않음)이 있으면
그 검사도 함께 돈다.

```bash
Rscript R/selfcheck.R        # 분석 계층 + run.R 왕복, 약 16초
```

`R/run.R` 직접 호출 예:

```bash
echo '{"action": "inspect", "args": {"path": "/path/to/file.bin"}}' > in.json
Rscript R/run.R in.json out.json     # 성공 0, 실패 1. out.json에 결과 또는 에러
```

ver.1.0(레거시)은 참고용으로만 보관한다. 2026-09-24에 분석 계층에서 그림(PNG) 저장 함수를
지웠기 때문에 ver.1.0 화면과 `r_runner.py` 셀프 체크는 더 이상 현재 R 코드로 실행되지 않는다.

측정 데이터(`*.bin`, `*.rda` 등)는 저장소에 커밋하지 않는다.
