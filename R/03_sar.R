# R/03_sar.R — ③ SAR: POSITION별 SAR로 De와 QC 판정을 얻는다.
# 소스 선량률(dose_rate_source, 초 -> Gy)은 이 단계의 analyse_SAR.CWOSL 인자로 들어간다.
# ============================================================
# Signal 단계에서 정한 signal/background integral로 POSITION별 SAR 분석을 돌려
# De 값을 얻는다. 여기서 나온 De 모음이 다음 단계(De 분포 -> CAM/MAM/FMM)의 입력이다.
#
# integral 문자열 파싱
# ---------------------
# 호출부(UI)는 "1:2" 같은 자유 입력 문자열을 넘긴다. 이건 신뢰 경계라서
# R로 넘어온 시점에 반드시 검증해야 한다. 검증 실패를 그대로 두면
# analyse_SAR.CWOSL()이 엉뚱한 채널을 적분하고도 에러 없이 De를 뱉는다.
.parse_integral <- function(value, label, n_points) {
  if (is.null(value) || length(value) != 1 || is.na(value) || !nzchar(value)) {
    stop(paste0(label, "이(가) 비어 있습니다. 예: 1:2"))
  }

  parts <- strsplit(trimws(as.character(value)), "[:,-]")[[1]]
  parts <- trimws(parts[nzchar(trimws(parts))])

  if (length(parts) != 2) {
    stop(paste0(label, " 형식이 올바르지 않습니다: '", value, "' / 예: 1:2"))
  }

  nums <- suppressWarnings(as.integer(parts))

  if (any(is.na(nums))) {
    stop(paste0(label, "에 숫자가 아닌 값이 있습니다: '", value, "' / 예: 1:2"))
  }

  if (nums[1] < 1) {
    stop(paste0(label, "의 시작 채널은 1 이상이어야 합니다: ", nums[1]))
  }

  if (nums[1] > nums[2]) {
    stop(
      paste0(
        label, "의 시작이 끝보다 큽니다: ", nums[1], ":", nums[2],
        " / 예: ", nums[2], ":", nums[1]
      )
    )
  }

  if (!is.na(n_points) && nums[2] > n_points) {
    stop(
      paste0(
        label, "이 측정 채널 수를 넘습니다: ", nums[1], ":", nums[2],
        " / 이 파일의 채널 수(NPOINTS): ", n_points
      )
    )
  }

  as.integer(nums)
}


# 분석 단위 하나(single-aliquot: POSITION, single-grain: POSITION+GRAIN)에 대해
# SAR을 돌리고 필요한 값만 뽑는다. found는 .position_records()의 반환값이다.
.run_sar_one <- function(found, signal_integral, background_integral) {

  # signal_integral/background_integral은 c(시작, 끝)이다. analyse_SAR.CWOSL()은 "적분할
  # 채널들의 벡터"를 받으므로 c(900, 1000)을 넘기면 900번·1000번 두 채널만 적분한다.
  # 반드시 시작:끝 전체를 넘긴다.
  res <- analyse_SAR.CWOSL(
    object = found$obj,
    signal_integral = seq(signal_integral[1], signal_integral[2]),
    background_integral = seq(background_integral[1], background_integral[2]),
    plot = FALSE,
    verbose = FALSE
  )

  if (is.null(res)) {
    stop("SAR 분석이 결과를 반환하지 않았습니다.")
  }

  data <- get_RLum(res, "data")

  if (is.null(data) || nrow(data) == 0) {
    stop("SAR 결과에 De 값이 없습니다.")
  }

  # 품질 지표는 rejection.criteria 표에 Criteria/Value 행으로 들어온다.
  # 기획서가 요구하는 recycling ratio / recuperation을 이름으로 찾아 꺼낸다.
  rc <- try(get_RLum(res, "rejection.criteria"), silent = TRUE)

  pick_rc <- function(pattern) {
    if (inherits(rc, "try-error") || is.null(rc) || nrow(rc) == 0) {
      return(NA_real_)
    }

    hit <- grep(pattern, rc$Criteria, ignore.case = TRUE)

    if (length(hit) == 0) {
      return(NA_real_)
    }

    as.numeric(rc$Value[hit[1]])
  }

  get_one <- function(col) {
    if (col %in% colnames(data)) data[[col]][1] else NA
  }

  # 발췌한 2개 지표만 넘기면 나머지 기준(testdose error, S/N 등)이 사라진다.
  # 연구자가 왜 FAILED인지 판단하려면 전 항목이 필요하므로 표를 통째로 넘긴다.
  if (inherits(rc, "try-error") || is.null(rc) || nrow(rc) == 0) {
    qc_criteria <- character(0)
    qc_value <- numeric(0)
    qc_threshold <- numeric(0)
    qc_status <- character(0)
  } else {
    qc_criteria <- as.character(rc$Criteria)
    qc_value <- suppressWarnings(as.numeric(rc$Value))
    qc_threshold <- suppressWarnings(as.numeric(rc$Threshold))
    qc_status <- as.character(rc$Status)
  }

  list(
    de = as.numeric(get_one("De")),
    de_error = as.numeric(get_one("De.Error")),
    rc_status = as.character(get_one("RC.Status")),
    fit = as.character(get_one("Fit")),
    n_n = as.numeric(get_one("n_N")),
    recycling_ratio = pick_rc("Recycling ratio"),
    recuperation = pick_rc("Recuperation"),
    qc_criteria = qc_criteria,
    qc_value = qc_value,
    qc_threshold = qc_threshold,
    qc_status = qc_status,

    res = res
  )
}



# 파일의 채널 수(NPOINTS 최대값)에 맞춰 적분 구간 문자열을 검증·변환한다.
.parse_integrals <- function(loaded, signal_integral, background_integral) {
  metadata <- loaded$metadata

  n_points <- if ("NPOINTS" %in% colnames(metadata)) {
    suppressWarnings(max(as.integer(metadata$NPOINTS), na.rm = TRUE))
  } else {
    NA_integer_
  }

  if (!is.finite(n_points)) {
    n_points <- NA_integer_
  }

  list(
    sig = .parse_integral(signal_integral, "Signal integral", n_points),
    bg = .parse_integral(background_integral, "Background integral", n_points)
  )
}

# 모드에 맞는 분석 대상 데이터. single-aliquot 모드에서 single-grain 파일이면
# convert_SG2MG()로 디스크별 grain 신호를 합산한다(De 평균이 아니다).
.mode_bin_data <- function(loaded, mode) {
  if (mode == "single_grain") {
    if (!loaded$single_grain) {
      stop(
        "single-grain 모드는 GRAIN 번호가 기록된 파일에서만 가능합니다. ",
        "이 파일은 single-aliquot 측정입니다."
      )
    }

    return(loaded$bin_data)
  }

  if (loaded$single_grain) convert_SG2MG(loaded$bin_data) else loaded$bin_data
}

# 진행률을 JSON 파일로 남긴다. 웹 계층(PHP)이 이 파일을 읽어 진행 바를 그린다.
# 임시 파일에 쓰고 rename 하므로, 읽는 쪽이 반쯤 쓰인 파일을 보지 않는다.
.write_progress <- function(progress_file, done, total) {
  if (is.null(progress_file)) {
    return(invisible(NULL))
  }

  tmp <- paste0(progress_file, ".tmp")
  writeLines(sprintf('{"done": %d, "total": %d}', as.integer(done), as.integer(total)), tmp)
  file.rename(tmp, progress_file)

  invisible(NULL)
}


# 선택한 POSITION들에 대해 SAR을 일괄 실행한다.
#
# mode:
#   "single_aliquot"  디스크(POSITION)마다 De 하나. single-grain 파일이면 먼저
#                     convert_SG2MG()로 디스크별 grain 신호를 합산한다(De 평균이 아니다).
#   "single_grain"    grain(POSITION+GRAIN)마다 De 하나. GRAIN 번호가 있는 파일만 가능.
#
#   한 단위가 실패해도 전체를 중단하지 않는다.
#   De 분포를 만들려면 De가 여러 개 필요한데, 그 중 하나가 fit 실패로 막힌다고
#   나머지 정상 결과까지 버리면 분석이 불가능해진다.
#   실패한 단위는 사유와 함께 따로 모아서 UI가 보여줄 수 있게 반환한다.
#
# progress_file을 주면 단위 하나가 끝날 때마다 {"done": i, "total": n}을 쓴다.
#
# seed: analyse_SAR.CWOSL()은 De 오차를 Monte Carlo로 추정하고, QC의 "Palaeodose error"가
# 그 오차로 판정한다. 시드를 고정하지 않으면 같은 입력에서도 경계의 grain이
# 통과/탈락을 오간다(실측: 49 grain 중 1개가 시드에 따라 뒤집힘). 단위마다 같은
# 시드를 걸어, 함께 선택된 다른 단위와 무관하게 판정이 재현되게 하고 결과에 기록한다.
run_sar_analysis <- function(path, positions, signal_integral, background_integral,
                             mode = "single_aliquot",
                             progress_file = NULL, seed = 1L) {
  loaded <- load_bin_data(path)

  mode <- match.arg(mode, c("single_aliquot", "single_grain"))

  if (is.null(positions) || length(positions) == 0) {
    stop("분석할 POSITION이 선택되지 않았습니다.")
  }

  positions <- sort(unique(as.integer(positions)))

  unknown <- setdiff(positions, loaded$positions)

  if (length(unknown) > 0) {
    stop(
      paste0(
        "파일에 없는 POSITION입니다: ",
        paste(unknown, collapse = ", ")
      )
    )
  }

  integrals <- .parse_integrals(loaded, signal_integral, background_integral)
  sig <- integrals$sig
  bg <- integrals$bg


  # ------------------------------------------------------------
  # 분석 단위 구성
  # ------------------------------------------------------------
  bin_data <- .mode_bin_data(loaded, mode)

  if (mode == "single_grain") {
    keep <- loaded$grain_position %in% positions
    unit_pos <- loaded$grain_position[keep]
    unit_grain <- loaded$grain[keep]
  } else {
    unit_pos <- positions
    unit_grain <- rep(NA_integer_, length(positions))
  }

  n_units <- length(unit_pos)

  ok_position <- integer(0)
  ok_grain <- integer(0)
  ok_de <- numeric(0)
  ok_de_error <- numeric(0)
  ok_rc_status <- character(0)
  ok_fit <- character(0)
  ok_n_n <- numeric(0)
  ok_recycling <- numeric(0)
  ok_recuperation <- numeric(0)
  ok_warning <- character(0)

  # QC 표는 단위당 여러 행이므로 position/grain 컬럼을 붙여 길게 쌓는다.
  qc_position <- integer(0)
  qc_grain <- integer(0)
  qc_criteria <- character(0)
  qc_value <- numeric(0)
  qc_threshold <- numeric(0)
  qc_status <- character(0)

  failed_position <- integer(0)
  failed_grain <- integer(0)
  failed_reason <- character(0)

  .write_progress(progress_file, 0L, n_units)

  for (i in seq_len(n_units)) {
    pos <- unit_pos[i]
    grain <- unit_grain[i]

    # 경고는 콘솔에만 찍히고 사라지므로 단위별로 모아 결과에 싣는다.
    # (적분 구간 형식 오류도 경고로만 드러났다.)
    unit_warnings <- character(0)

    set.seed(seed)
    one <- try(
      withCallingHandlers(
        .run_sar_one(
          .position_records(bin_data, pos, if (is.na(grain)) NULL else grain),
          sig, bg
        ),
        warning = function(w) {
          unit_warnings <<- c(unit_warnings, conditionMessage(w))
          invokeRestart("muffleWarning")
        }
      ),
      silent = TRUE
    )

    .write_progress(progress_file, i, n_units)

    if (inherits(one, "try-error")) {
      failed_position <- c(failed_position, pos)
      failed_grain <- c(failed_grain, grain)
      failed_reason <- c(
        failed_reason,
        trimws(as.character(attr(one, "condition")$message))
      )

      next
    }

    ok_position <- c(ok_position, pos)
    ok_grain <- c(ok_grain, grain)
    ok_de <- c(ok_de, one$de)
    ok_de_error <- c(ok_de_error, one$de_error)
    ok_rc_status <- c(ok_rc_status, one$rc_status)
    ok_fit <- c(ok_fit, one$fit)
    ok_n_n <- c(ok_n_n, one$n_n)
    ok_recycling <- c(ok_recycling, one$recycling_ratio)
    ok_recuperation <- c(ok_recuperation, one$recuperation)
    ok_warning <- c(ok_warning, paste(unique(unit_warnings), collapse = " | "))

    n_rows <- length(one$qc_criteria)

    if (n_rows > 0) {
      qc_position <- c(qc_position, rep(pos, n_rows))
      qc_grain <- c(qc_grain, rep(grain, n_rows))
      qc_criteria <- c(qc_criteria, one$qc_criteria)
      qc_value <- c(qc_value, one$qc_value)
      qc_threshold <- c(qc_threshold, one$qc_threshold)
      qc_status <- c(qc_status, one$qc_status)
    }
  }

  if (length(ok_position) == 0) {
    stop(
      paste0(
        "선택한 분석 단위 ", n_units, "개 전부 SAR 분석에 실패했습니다. ",
        "첫 번째 사유: ",
        if (length(failed_reason) > 0) failed_reason[1] else "(사유 없음)"
      )
    )
  }

  # 디스크별 요약: 분석 단위 수(single-grain이면 grain 수)와 QC 통과 수.
  disc <- sort(unique(unit_pos))
  disc_n_units <- as.integer(table(factor(unit_pos, levels = disc)))
  disc_n_accepted <- as.integer(table(factor(ok_position[ok_rc_status == "OK"], levels = disc)))

  list(
    mode = mode,
    seed = as.integer(seed),
    signal_integral = as.integer(sig),
    background_integral = as.integer(bg),

    n_requested = as.integer(n_units),
    n_success = as.integer(length(ok_position)),
    n_failed = as.integer(length(failed_position)),

    position = as.integer(ok_position),
    grain = as.integer(ok_grain),
    de = as.numeric(ok_de),
    de_error = as.numeric(ok_de_error),
    rc_status = as.character(ok_rc_status),
    fit = as.character(ok_fit),
    n_n = as.numeric(ok_n_n),
    recycling_ratio = as.numeric(ok_recycling),
    recuperation = as.numeric(ok_recuperation),
    warning = as.character(ok_warning),

    qc_position = as.integer(qc_position),
    qc_grain = as.integer(qc_grain),
    qc_criteria = as.character(qc_criteria),
    qc_value = as.numeric(qc_value),
    qc_threshold = as.numeric(qc_threshold),
    qc_status = as.character(qc_status),

    failed_position = as.integer(failed_position),
    failed_grain = as.integer(failed_grain),
    failed_reason = as.character(failed_reason),

    disc_position = as.integer(disc),
    disc_n_units = disc_n_units,
    disc_n_accepted = disc_n_accepted
  )
}


# 분석 단위 하나의 선량-반응 곡선을 그래프용 데이터로 반환한다(브라우저가 그린다).
# run_sar_analysis()와 같은 데이터·같은 시드로 계산하므로 De가 표와 일치한다.
#
# points: SAR 측정점. Natural(자연 신호), R1..(재생 선량), Repeated=TRUE(recycling 반복점),
#         Dose 0 재생점(recuperation). 선량 단위는 파일의 IRR_TIME 그대로(현재 초).
# curve : 적합식 Formula를 격자에서 계산한 곡선. Luminescence가 Formula의 계수를
#         유효숫자 3자리로 반올림해 두므로 표시용이다(De 지점에서 ~0.03% 차이 확인).
#         De 값 자체는 반올림 전 적합으로 계산된 것이다.
get_dose_response <- function(path, pos, signal_integral, background_integral,
                              grain = NULL, mode = "single_aliquot", seed = 1L,
                              n_curve = 100L) {
  loaded <- load_bin_data(path)
  mode <- match.arg(mode, c("single_aliquot", "single_grain"))
  integrals <- .parse_integrals(loaded, signal_integral, background_integral)
  bin_data <- .mode_bin_data(loaded, mode)

  if (mode == "single_grain" && is.null(grain)) {
    stop("single-grain 모드에서는 GRAIN을 지정해야 합니다.")
  }

  if (mode == "single_aliquot") {
    grain <- NULL
  }

  set.seed(seed)
  one <- .run_sar_one(.position_records(bin_data, pos, grain), integrals$sig, integrals$bg)

  tab <- get_RLum(one$res, "LnLxTnTx.table")
  formula <- one$res@data$Formula

  curve_x <- numeric(0)
  curve_y <- numeric(0)

  if (is.expression(formula) && length(tab$Dose) > 0) {
    x_max <- max(c(tab$Dose, one$de), na.rm = TRUE) * 1.1
    x <- seq(0, x_max, length.out = n_curve)
    y <- try(eval(formula[[1]], list(x = x)), silent = TRUE)

    if (!inherits(y, "try-error") && length(y) == length(x)) {
      curve_x <- x
      curve_y <- as.numeric(y)
    }
  }

  list(
    position = as.integer(pos),
    grain = if (is.null(grain)) NA_integer_ else as.integer(grain),
    mode = mode,
    seed = as.integer(seed),
    signal_integral = as.integer(integrals$sig),
    background_integral = as.integer(integrals$bg),
    de = one$de,
    de_error = one$de_error,
    rc_status = one$rc_status,
    fit = one$fit,
    formula = if (is.expression(formula)) paste(deparse(formula[[1]]), collapse = "") else NA_character_,
    points = data.frame(
      name = as.character(tab$Name),
      dose = as.numeric(tab$Dose),
      lxtx = as.numeric(tab$LxTx),
      lxtx_error = as.numeric(tab$LxTx.Error),
      repeated = as.logical(tab$Repeated)
    ),
    curve_x = curve_x,
    curve_y = curve_y
  )
}
