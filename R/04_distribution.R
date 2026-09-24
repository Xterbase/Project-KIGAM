# R/04_distribution.R — ④ 분포 진단: De 표 -> OD, 왜도/첨도, FMM BIC, radial/abanico plot.
# numOSL sensSAM(조건부 도입)은 이 단계의 지표와 ⑤ 연령 모델 사이, 모델 선택 근거로 들어간다.
# ============================================================
# SAR에서 나온 De 모음(De 값 + 오차)을 받아 분포 특성을 계산하고,
# radial/abanico plot을 PNG로 저장한다. 여기서 나온 지표(OD, 왜도, 다봉성)가
# 다음 단계(CAM/MAM/FMM 추천)의 입력이다.
#
# 통계는 Luminescence 패키지 함수를 그대로 쓴다(프로젝트 원칙: 재구현하지 않는다):
#   - OD(과분산)   : calc_CentralDose(CAM). summary의 OD(Gy) / rel_OD(%)
#   - 왜도/첨도     : calc_Statistics. weighted/unweighted skewness, kurtosis
#
# 다봉성(FMM 적용 여부) 판정은 여기서 하지 않는다. OSL 문헌의 표준은 성분 수를
# 바꿔가며 적합해 BIC를 비교하는 것(calc_FiniteMixture)이지 KDE mode 수 세기가
# 아니다. KDE mode count는 소표본에서 대역폭에 따라 3~4개까지 요동쳐 신뢰할 수
# 없음을 fixture(BT998, n=25)로 확인했다. 따라서 다봉성 판정은 정석 방법으로
# 다음 단계(모델 추천)에서 처리하고, 이 함수는 OD/왜도/첨도 같은 견고한 지표만 낸다.

# output_dir을 주면 radial/abanico PNG를 저장한다. 안 주면 지표만 계산한다
# (r_runner self-check처럼 그림이 필요 없는 호출을 위해).
analyse_de_distribution <- function(de, de_error, output_dir = NULL, prefix = "de_dist") {
  # --- 입력 검증 ---
  de <- as.numeric(de)
  de_error <- as.numeric(de_error)

  if (length(de) == 0) {
    stop("De 값이 비어 있습니다.")
  }

  if (length(de) != length(de_error)) {
    stop(
      paste0(
        "De 값과 오차의 개수가 다릅니다: ",
        length(de), " vs ", length(de_error)
      )
    )
  }

  # NA/비유한 값이 섞이면 통계 함수가 실패하므로 걸러낸다.
  # 몇 개를 버렸는지는 반환값에 실어 UI가 알 수 있게 한다.
  ok <- is.finite(de) & is.finite(de_error)
  n_dropped <- sum(!ok)
  de <- de[ok]
  de_error <- de_error[ok]

  n <- length(de)

  if (n < 3) {
    stop(
      paste0(
        "De 분포 분석에는 최소 3개의 유효한 De 값이 필요합니다 (현재 ", n, "개)."
      )
    )
  }

  # 음수/0 De는 로그 기반 모델(CAM/MAM/FMM)을 적용할 수 없다. calc_CentralDose는
  # log=TRUE 기본에서 음수를 만나면 콘솔 경고만 남기고 조용히 선형 모드로 강등해
  # 로그 도메인 임계값과 비교 불가능한 OD를 내놓는다. 그 전에 명시적으로 막는다.
  # 관례상 음수 De는 버리지 않고 unlogged 모델로 다루지만(Galbraith & Roberts 2012),
  # unlogged 경로는 아직 미지원이라 지금은 중단한다.
  # single-grain(음수 De 흔함) 지원 시 unlogged MAM/CAM 경로 추가.
  n_nonpositive <- sum(de <= 0)
  if (n_nonpositive > 0) {
    stop(
      paste0(
        "음수 또는 0인 De ", n_nonpositive, "개가 있어 로그 기반 모델",
        "(CAM/MAM/FMM)을 적용할 수 없습니다. 음수 De는 unlogged 모델로 ",
        "다뤄야 하나 아직 미지원입니다."
      )
    )
  }

  # Luminescence 함수는 앞 두 컬럼을 위치로 받는다(이름 무관).
  data <- data.frame(De = de, De.Error = de_error)

  # --- OD: CAM ---
  cam <- calc_CentralDose(data, verbose = FALSE, plot = FALSE)
  cam_summary <- get_RLum(cam, "summary")

  # --- 왜도/첨도 ---
  stats <- calc_Statistics(data)

  # --- plot 저장 (output_dir 있을 때만) ---
  radial_file <- NA_character_
  abanico_file <- NA_character_

  if (!is.null(output_dir) && !is.na(output_dir) && nzchar(output_dir)) {
    if (!dir.exists(output_dir)) {
      dir.create(output_dir, recursive = TRUE)
    }

    output_dir <- normalizePath(output_dir, winslash = "/", mustWork = TRUE)

    radial_file <- .save_png(
      file.path(output_dir, paste0(prefix, "_radial.png")),
      function() plot_RadialPlot(data),
      width = 1400, height = 1000, res = 150, label = "De 분포 plot"
    )

    abanico_file <- .save_png(
      file.path(output_dir, paste0(prefix, "_abanico.png")),
      function() plot_AbanicoPlot(data),
      width = 1400, height = 1000, res = 150, label = "De 분포 plot"
    )
  }

  list(
    n = as.integer(n),
    n_dropped = as.integer(n_dropped),

    # CAM / 과분산
    central_de = as.numeric(cam_summary$de),
    central_de_error = as.numeric(cam_summary$de_err),
    od_abs = as.numeric(cam_summary$OD),
    od_abs_error = as.numeric(cam_summary$OD_err),
    od_rel = as.numeric(cam_summary$rel_OD),
    od_rel_error = as.numeric(cam_summary$rel_OD_err),

    # 형태
    skewness = as.numeric(stats$unweighted$skewness),
    skewness_weighted = as.numeric(stats$weighted$skewness),
    kurtosis = as.numeric(stats$unweighted$kurtosis),

    # 퍼짐
    mean_de = as.numeric(stats$unweighted$mean),
    median_de = as.numeric(stats$unweighted$median),
    sd_rel = as.numeric(stats$unweighted$sd.rel),

    radial_plot_file = as.character(radial_file),
    abanico_plot_file = as.character(abanico_file),

    # 브라우저에서 그릴 데이터. de/de_error는 NA를 거른 뒤의 값(radial과 같은 순서).
    # 방사형 그래프(Galbraith 1988) 좌표: z = log(De), s = 상대오차(De.Error/De),
    #   x = 1/s(정밀도), y = (z - log(CAM 중심값)) / s(표준화 거리).
    # 원점에서 같은 직선 위의 점은 같은 De다. 통계가 아니라 표시용 좌표 변환이다.
    de = as.numeric(de),
    de_error = as.numeric(de_error),
    radial_x = as.numeric(de / de_error),
    radial_y = as.numeric((log(de) - log(cam_summary$de)) / (de_error / de))
  )
}


# ------------------------------------------------------------
# FMM 다봉성 판정용 BIC 비교
# ------------------------------------------------------------
# calc_FiniteMixture로 성분 수 k=2..max_k를 적합하고, 단일성분(k=1) 대비
# BIC를 비교한다. "다봉이다"라는 판정 자체는 여기서 하지 않는다 — 그 임계값은
# 추천 로직(model_recommend.py) 소관이고, 이 함수는 비교에 필요한 BIC만 낸다.
# 이산 혼합 여부를 성분 수별 BIC로 고르는 것은 OSL 문헌의 표준이다
# (Galbraith & Green 1990; Roberts et al. 2000; David et al. 2007).
#
# sigmab(성분 내 과분산 가정치)에 결과가 민감하다. CA1 fixture에서 sigmab
# 0.15면 다성분, 0.30이면 단일성분으로 판정이 뒤집힌다. 그래서 sigmab을 인자로
# 받아 반환값에 실어, 어떤 값으로 판정했는지 기록에 남긴다.
.fmm_max_k <- function(n) as.integer(n %/% 2L)

fit_finite_mixture <- function(de, de_error, sigmab = 0.15, max_k = 4L) {
  de <- as.numeric(de)
  de_error <- as.numeric(de_error)

  ok <- is.finite(de) & is.finite(de_error)
  de <- de[ok]
  de_error <- de_error[ok]

  n <- length(de)

  # 성분 k개 FMM의 모수는 2k-1개(선량 k + 비율 k-1, sigmab 고정)라서 De가 2k개 이상
  # 있어야 한다. 예전 상한(n-1)은 De 4개로 k=3(모수 5개)까지 적합해 BIC 비교가 무의미했다.
  max_k <- min(as.integer(max_k), .fmm_max_k(n))

  if (n < 4 || max_k < 2L) {
    stop(paste0("FMM 적합에는 최소 4개의 유효한 De 값이 필요합니다 (현재 ", n, "개)."))
  }

  data <- data.frame(De = de, De.Error = de_error)

  res <- calc_FiniteMixture(
    data,
    sigmab = sigmab,
    n.components = 2:max_k,
    verbose = FALSE,
    plot = FALSE
  )

  bic <- res@data$BIC                         # cols: n.components, BIC
  single_bic <- as.numeric(res@data$single.comp$BIC)
  best_i <- which.min(bic$BIC)

  list(
    sigmab = as.numeric(sigmab),
    single_bic = single_bic,
    k = as.integer(bic$n.components),
    bic = as.numeric(bic$BIC),
    best_k = as.integer(bic$n.components[best_i]),
    best_bic = as.numeric(bic$BIC[best_i]),

    # >0이면 다성분(k>=2)이 단일성분보다 BIC가 낮다(더 낫다)는 뜻.
    delta_bic = as.numeric(single_bic - min(bic$BIC))
  )
}

