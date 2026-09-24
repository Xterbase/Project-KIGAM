# R/selfcheck.R — 분석 계층 자가 점검. 실행: Rscript R/selfcheck.R
#
# 기대값은 Luminescence 1.2.1 실측치다(적분 구간 전체를 넘기도록 고친 뒤, 2026-09-24). 벗어나면 패키지를 올렸거나 계산이 바뀐 것이고,
# 어느 쪽인지는 연대값에 직접 영향을 주므로 사람이 판단해야 한다.
# single-grain 검사는 test_data/(gitignore, 측정 데이터)가 있을 때만 돈다.

script_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
here <- dirname(normalizePath(sub("^--file=", "", script_arg)))
source(file.path(here, "Analysis.R"))

tmp <- tempfile("selfcheck_")
dir.create(tmp)

expect_error <- function(expr, pattern) {
  msg <- tryCatch({ expr; NA_character_ }, error = function(e) conditionMessage(e))
  stopifnot("에러가 나야 하는데 통과했다" = !is.na(msg), grepl(pattern, msg))
}

png_ok <- function(f) file.exists(f) && file.info(f)$size > 0

# ------------------------------------------------------------
# 1. single-aliquot 기준선 (패키지 예제 데이터로 fixture 생성)
# ------------------------------------------------------------
data(ExampleData.BINfileData, package = "Luminescence", envir = environment())
fixture <- file.path(tmp, "fixture.rda")
save(CWOSL.SAR.Data, file = fixture)

info <- inspect_positions(fixture)
stopifnot(
  "POSITION 24개" = identical(info$positions, 1:24),
  "예제 데이터는 single-aliquot" = !info$single_grain
)

progress <- file.path(tmp, "progress.json")
sar <- run_sar_analysis(fixture, 1:24, "1:2", "900:1000",
                        plot_dir = file.path(tmp, "sar"), progress_file = progress)

stopifnot(
  "24/24 분석" = sar$n_success == 24,
  "QC 통과 21개" = sum(sar$rc_status == "OK") == 21,
  "POSITION 8, 11, 22 탈락" = identical(sar$position[sar$rc_status != "OK"], c(8L, 11L, 22L)),
  "De 범위 673.1–1883.3 s" = min(sar$de) > 673 && max(sar$de) < 1884,
  "POSITION 1 De 1668.3" = abs(sar$de[1] - 1668.3) < 0.1,
  "POSITION 2 De 1534.5" = abs(sar$de[2] - 1534.5) < 0.1,
  # 적분 구간을 c(시작, 끝)로 넘기면 두 채널만 적분되고 이 경고가 난다(과거 결함).
  "적분 구간 경고 없음" = !any(grepl("please check your input", sar$warning)),
  "single-aliquot는 grain NA" = all(is.na(sar$grain)),
  "dose-response PNG" = png_ok(sar$plot_file[1]),
  "진행률 파일 완료 표시" = identical(readLines(progress), '{"done": 24, "total": 24}')
)

expect_error(
  run_sar_analysis(fixture, 1:2, "1:2", "900:1000", mode = "single_grain"),
  "GRAIN 번호가 기록된 파일에서만"
)

curve <- save_rlum_record_plot(fixture, 1, 2, file.path(tmp, "curve"))
stopifnot("곡선 PNG" = png_ok(curve$plot_file))

cat("[OK] single-aliquot 기준선\n")

# ------------------------------------------------------------
# 2. single-grain 파일: A(grain별)와 B(디스크별, convert_SG2MG)
#    적분 구간 6:10은 레이저 켜진 뒤 구간이다(앞 5채널은 레이저 꺼짐).
# ------------------------------------------------------------
sg_cases <- list(
  list(file = "bin.BIN",  n_pos = 11, a_ok = 4, a_de = c(1195, 2428), b_ok = c(1L, 7L, 8L)),
  list(file = "bin2.BIN", n_pos = 21, a_ok = 3, a_de = c(1157, 1339), b_ok = c(5L, 7L, 8L))
)

for (case in sg_cases) {
  f <- file.path(here, "..", "test_data", case$file)

  if (!file.exists(f)) {
    cat("[SKIP]", case$file, "없음\n")
    next
  }

  info <- inspect_positions(f)
  stopifnot(
    "single-grain 판별" = info$single_grain,
    "grain 49개" = length(info$grain) == 49,
    "디스크 수" = info$n_positions == case$n_pos
  )

  p1 <- info$grain_position[1]
  g1 <- info$grain[1]

  # grain이 여러 개인 디스크는 GRAIN 없이 요청하면 막혀야 한다(곡선 어긋남 방지).
  p_multi <- as.integer(names(which(table(info$grain_position) > 1))[1])
  expect_error(inspect_rlum_records_by_position(f, p_multi), "GRAIN을 지정해야")

  recs <- inspect_rlum_records_by_position(f, p1, grain = g1)
  stopifnot("grain 하나의 record" = recs$n_records %in% c(16L, 18L), recs$grain == g1)

  curve <- save_rlum_record_plot(f, p1, 1, file.path(tmp, "sg_curve"), grain = g1)
  stopifnot("grain 곡선 PNG" = png_ok(curve$plot_file), grepl("_grain_", curve$plot_file))

  a <- run_sar_analysis(f, info$positions, "6:10", "81:100", mode = "single_grain")
  a_de <- a$de[a$rc_status == "OK"]
  stopifnot(
    "A: 단위 49개" = a$n_requested == 49,
    "A: QC 통과 수" = length(a_de) == case$a_ok,
    "A: De 범위" = all(a_de >= case$a_de[1] & a_de <= case$a_de[2]),
    "A: 디스크별 grain 합" = sum(a$disc_n_units) == 49,
    "A: 디스크별 통과 합" = sum(a$disc_n_accepted) == case$a_ok
  )

  # 재현성: 다른 전역 난수 상태에서도, 일부 디스크만 골라도 같은 grain은 같은 판정이어야 한다.
  set.seed(999)
  a2 <- run_sar_analysis(f, info$positions[1:3], "6:10", "81:100", mode = "single_grain")
  k <- match(paste(a2$position, a2$grain), paste(a$position, a$grain))
  stopifnot(
    "A: 시드 기록" = a$seed == 1L,
    "A: 재현성(De)" = identical(a2$de, a$de[k]),
    "A: 재현성(판정)" = identical(a2$rc_status, a$rc_status[k])
  )

  b <- run_sar_analysis(f, info$positions, "6:10", "81:100", mode = "single_aliquot")
  stopifnot(
    "B: 디스크당 하나" = b$n_requested == case$n_pos,
    "B: QC 통과 디스크" = identical(b$position[b$rc_status == "OK"], case$b_ok)
  )

  cat("[OK]", case$file, "A/B\n")
}

# ------------------------------------------------------------
# 3. ⑤ 연령 모델: 규칙은 model_recommend.py의 회귀 기준과 같아야 한다.
#    CA1(n=62): OD 34.7%, 대칭, ΔBIC 95.5 -> FMM(k=3) / BT998(n=25): OD 8.0% -> CAM
# ------------------------------------------------------------
data(ExampleData.DeValues, package = "Luminescence", envir = environment())
ca1 <- ExampleData.DeValues$CA1
bt <- ExampleData.DeValues$BT998

r_ca1 <- run_age_model(ca1[[1]], ca1[[2]], sigmab = 0.15)
stopifnot(
  "CA1 -> FMM" = r_ca1$recommendation$model == "FMM",
  "CA1 ΔBIC" = abs(r_ca1$recommendation$fmm_delta_bic - 95.5) < 0.1,
  "CA1 성분 3개" = r_ca1$result$n_components == 3,
  "CA1 성분 비율 합 1" = abs(sum(r_ca1$result$component_proportion) - 1) < 0.01,
  "FMM은 성분을 고르지 않는다" = is.na(r_ca1$result$dose),
  "규칙 선택 기록" = r_ca1$model_source == "rule"
)

r_bt <- run_age_model(bt[[1]], bt[[2]], sigmab = 0.15)
stopifnot(
  "BT998 -> CAM" = r_bt$recommendation$model == "CAM",
  "BT998 CAM 선량" = abs(r_bt$result$dose - 2936) < 1,
  "CAM은 sigmab 미사용" = is.na(r_bt$result$sigmab),
  "패키지 버전 기록" = r_bt$result$package_version == as.character(packageVersion("Luminescence"))
)

m_ca1 <- run_age_model(ca1[[1]], ca1[[2]], sigmab = 0.15, model = "MAM")
stopifnot(
  "사용자 선택 기록" = m_ca1$model_source == "user",
  "추천은 그대로 남음" = m_ca1$recommendation$model == "FMM",
  "MAM sigmab 기록" = m_ca1$result$sigmab == 0.15,
  "CA1 MAM 선량" = abs(m_ca1$result$dose - 40.09) < 0.1
)

expect_error(apply_age_model(bt[[1]], bt[[2]], "MAM"), "sigmab")
expect_error(apply_age_model(c(10, 12, 11, 13), c(1, 1, 1, 1), "FMM", sigmab = 0.2, n_components = 3), "De가 6개 이상")

# 예제 데이터 끝까지: QC 통과 21개 -> OD 18.9% -> CAM
acc <- sar$rc_status == "OK"
r_ex <- run_age_model(sar$de[acc], sar$de_error[acc], sigmab = 0.15)
stopifnot(
  "예제 -> CAM" = r_ex$recommendation$model == "CAM",
  "예제 CAM 선량 1391.9" = abs(r_ex$result$dose - 1391.9) < 0.1
)

cat("[OK] ⑤ 연령 모델\n")

# ------------------------------------------------------------
# 4. run.R (웹 계층 진입점): PHP가 부르는 방식 그대로 Rscript로 실행한다.
#    브라우저가 믿는 JSON 규칙(배열은 원소 1개여도 배열, 표는 행 객체 배열)을 고정한다.
# ------------------------------------------------------------
library(jsonlite)

call_run <- function(action, args) {
  inp <- tempfile(fileext = ".json", tmpdir = tmp)
  out <- tempfile(fileext = ".json", tmpdir = tmp)
  write_json(list(action = action, args = args), inp, auto_unbox = TRUE, digits = NA)
  status <- system2(file.path(R.home("bin"), "Rscript"), c(file.path(here, "run.R"), inp, out),
                    stdout = FALSE, stderr = FALSE)
  c(fromJSON(out, simplifyVector = FALSE), list(status = status))
}

r <- call_run("inspect", list(path = fixture))
stopifnot(
  "inspect 성공" = r$ok && r$status == 0,
  "records 표" = length(r$result$records) == nrow(CWOSL.SAR.Data@METADATA),
  "positions 배열" = length(r$result$positions) == 24
)

r <- call_run("curve", list(path = fixture, position = 1, record_index = 2))
stopifnot("curve 데이터" = r$ok && length(r$result$x) == length(r$result$y) && length(r$result$x) > 1)

prog <- file.path(tmp, "run_progress.json")
r <- call_run("sar", list(path = fixture, positions = 1, signal_integral = "1:2",
                          background_integral = "900:1000", progress_file = prog))
stopifnot(
  "sar 성공" = r$ok,
  "POSITION 1개여도 units는 배열" = is.list(r$result$units) && length(r$result$units) == 1,
  "sar De = R 직접 계산" = abs(r$result$units[[1]]$de - sar$de[1]) < 1e-9,
  "적분 구간 배열" = length(r$result$signal_integral) == 2,
  "진행률" = identical(readLines(prog), '{"done": 1, "total": 1}')
)

r <- call_run("dose_response", list(path = fixture, position = 1, signal_integral = "1:2",
                                    background_integral = "900:1000"))
stopifnot(
  "dose_response De = 표" = r$ok && abs(r$result$de - sar$de[1]) < 1e-9,
  "측정점 표" = length(r$result$points) >= 5,
  "곡선 데이터" = length(r$result$curve_x) == 100
)

r <- call_run("age_model", list(de = ca1[[1]], de_error = ca1[[2]], sigmab = 0.15))
stopifnot(
  "age_model 성공" = r$ok,
  "FMM 성분 표" = length(r$result$result$components) == 3,
  "FMM dose는 null" = is.null(r$result$result$dose),
  "방사형 좌표" = length(r$result$distribution$points) == 62,
  "추천 근거 배열" = is.list(r$result$recommendation$reasons)
)

r <- call_run("nope", list())
stopifnot("잘못된 동작은 실패" = !r$ok && r$status == 1 && grepl("알 수 없는 동작", r$error))

r <- call_run("inspect", list(path = file.path(tmp, "없는파일.bin")))
stopifnot("R 에러가 JSON으로 전달" = !r$ok && r$status == 1 && grepl("찾을 수 없습니다", r$error))

cat("[OK] run.R\n")

unlink(tmp, recursive = TRUE)
cat("selfcheck OK\n")
