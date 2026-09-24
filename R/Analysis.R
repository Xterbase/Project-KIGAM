# R/Analysis.R — 분석 계층 진입점. source() 하면 단계별 파일을 순서대로 불러온다.
#
# 파이프라인(파일 = 단계):
#   01_load.R          ① 로드        파일 경로 -> Risoe.BINfileData (+캐시, 공통 PNG 저장)
#   02_signal.R        ② 신호        BINfileData -> POSITION별 RLum.Analysis, 곡선
#   03_sar.R           ③ SAR         RLum.Analysis + 적분 구간 -> De 표 + QC
#   04_distribution.R  ④ 분포 진단    De 표 -> OD, 왜도, FMM BIC
#   05_models.R        ⑤ 연령 모델    De 표 -> 규칙 추천 -> CAM/MAM/FMM 선량
#   (⑥ 선량률·연령은 미구현: 선량률 입력 대기)
#
# 조건부 도입 패키지의 삽입 지점은 CLAUDE.md "Package review conclusions" 참고.

library(Luminescence)

local({
  # 이 파일의 위치 = 가장 안쪽 source() 프레임의 ofile. 작업 디렉터리나
  # 다른 스크립트 안에서 source() 됐는지(중첩)와 무관하게 동작해야 한다.
  ofiles <- Filter(Negate(is.null), lapply(sys.frames(), function(f) f$ofile))  # "지금 실행 중인 이 파일은 어디에 있는가?" 
  # sys.frames(): 현재 호출 스택에 쌓인 함수 프레임 목록
  here <- dirname(normalizePath(ofiles[[length(ofiles)]], winslash = "/"))

  for (f in c("01_load.R", "02_signal.R", "03_sar.R", "04_distribution.R", "05_models.R")) {
    source(file.path(here, f), local = globalenv())
  }
})
