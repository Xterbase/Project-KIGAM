# R/05_models.R — ⑤ 연령 모델: De 표 -> 모델 추천(규칙) -> 선택된 모델로 매몰선량 계산.
#
#   recommend_age_model()  ④의 지표를 CAM/MAM/FMM으로 매핑하는 결정적 규칙
#   apply_age_model()      선택된 모델 하나를 적용해 선량을 낸다
#   run_age_model()        ④ 지표 + FMM BIC + 추천 + 적용을 한 번에(웹 계층의 진입점)
#
# 규칙은 version1_streamlit/utils/model_recommend.py를 그대로 옮긴 것이다(선택을
# R 한 곳에서 재현하기 위해). 
# 게이트 순서(왜도 MAM이 다봉 FMM보다 먼저)는 다봉 자료에서 틀릴 수 있는 알려진 결함이지만, 출판 연대를 바꾸므로 전문가 검토 전에는 바꾸지 않는다.
#
# numOSL mcMAM/mcFMM(조건부 도입)은 apply_age_model() 옆에서 비교용으로 들어간다.
#
# 임계값 출처 (model_recommend.py와 동일):
#   OD 20%     : 잘 표백된 single-grain 석영도 과분산 ~20%가 전형 (Arnold & Roberts 2009;
#                Galbraith & Roberts 2012)
#   ΔBIC 6     : Kass & Raftery (1995)의 "strong evidence" 하한
#   왜도 유의성 : 2 × SES, SES = sqrt(6n(n-1)/((n-2)(n+1)(n+3))); 부분 표백 진단 (Bailey & Arnold 2006)

.MODEL_THRESHOLDS <- list(od_low_pct = 20, bic_strong = 6)

.skewness_se <- function(n) {
  sqrt(6 * n * (n - 1) / ((n - 2) * (n + 1) * (n + 3)))
}

# fmm: fit_finite_mixture()의 결과 또는 NULL(표본 부족·미수렴 등으로 미적합).
recommend_age_model <- function(od_rel, skewness, n, fmm = NULL) {
  n <- as.integer(n)

  # OD 게이트가 트리의 뿌리다. OD가 없으면 판정 자체가 불가능하다.
  if (is.null(od_rel) || !is.finite(od_rel)) {
    stop("OD(과분산)를 계산할 수 없어(분산 없음 등) 모델을 추천할 수 없습니다.")
  }

  th <- .MODEL_THRESHOLDS
  skew_crit <- 2 * .skewness_se(n)
  skew_known <- !is.null(skewness) && is.finite(skewness)
  positively_skewed <- skew_known && skewness > skew_crit
  dbic <- if (is.null(fmm)) NA_real_ else fmm$delta_bic
  multimodal <- is.finite(dbic) && dbic > th$bic_strong

  reasons <- character(0)

  if (od_rel < th$od_low_pct) {
    model <- "CAM"
    reasons <- c(reasons, sprintf("과분산 %.1f%% < %.0f%% → 잘 표백된 단일 집단", od_rel, th$od_low_pct))
  } else if (positively_skewed) {
    model <- "MAM"
    reasons <- c(reasons, sprintf(
      "과분산 %.1f%% 높음 + 양의 왜도 %.2f > 임계 %.2f → 부분 표백(비대칭 상향 꼬리)",
      od_rel, skewness, skew_crit
    ))
  } else if (multimodal) {
    model <- "FMM"
    reasons <- c(reasons, sprintf(
      "과분산 높음, 유의한 왜도 없음, BIC가 성분 %d개를 단일 대비 ΔBIC %.1f(>%.0f)로 선호 → 이산 혼합",
      fmm$best_k, dbic, th$bic_strong
    ))
  } else {
    model <- "CAM"
    reasons <- c(reasons, sprintf(
      "과분산 %.1f%% 높으나 유의한 왜도·다봉 근거 없음 → CAM(과분산 큼에 유의)", od_rel
    ))
    if (is.null(fmm)) {
      reasons <- c(reasons, "FMM 미적합(표본 부족 등)으로 다봉성 확인 못 함")
    }
  }

  if (!skew_known && od_rel >= th$od_low_pct) {
    reasons <- c(reasons, "왜도 계산 불가(분산 부족 등)로 부분 표백(MAM) 판정 건너뜀")
  }

  list(
    model = model,
    reasons = reasons,
    od_rel = as.numeric(od_rel),
    skewness = if (skew_known) as.numeric(skewness) else NA_real_,
    skew_crit = as.numeric(skew_crit),
    positively_skewed = positively_skewed,
    multimodal = multimodal,
    n = n,
    fmm_delta_bic = as.numeric(dbic),
    fmm_best_k = if (is.null(fmm)) NA_integer_ else as.integer(fmm$best_k),
    od_low_pct = th$od_low_pct,
    bic_strong = th$bic_strong
  )
}


# 선택된 모델 하나를 적용한다. 로그 모델이므로 De > 0이어야 한다(④와 같은 이유).
#
#   CAM  calc_CentralDose : 중심 선량 + 과분산
#   MAM  calc_MinDose     : 최소 선량. sigmab = "잘 표백됐다면 기대되는 과분산"(비율, 0.2 = 20%)
#   FMM  calc_FiniteMixture(n.components = k) : 성분별 선량·오차·비율.
#        어느 성분이 연대 대상인지는 퇴적 맥락에 따른 연구자 판단이므로 고르지 않는다
#        (dose는 NA, 성분 표만 반환).
#
# 결과에는 모델·sigmab·패키지 이름과 버전을 기록한다(판단 파라미터 기록 원칙).
apply_age_model <- function(de, de_error, model, sigmab = NULL, n_components = NULL,
                            mam_par = 3L) {
  model <- match.arg(model, c("CAM", "MAM", "FMM"))

  de <- as.numeric(de)
  de_error <- as.numeric(de_error)

  if (length(de) != length(de_error)) {
    stop("De 값과 오차의 개수가 다릅니다: ", length(de), " vs ", length(de_error))
  }

  ok <- is.finite(de) & is.finite(de_error)
  de <- de[ok]
  de_error <- de_error[ok]
  n <- length(de)

  if (any(de <= 0)) {
    stop("음수 또는 0인 De ", sum(de <= 0), "개가 있어 로그 기반 모델을 적용할 수 없습니다.")
  }

  # 모수 개수 이하의 표본으로는 추정 자체가 성립하지 않는다.
  n_par <- switch(model, CAM = 2L, MAM = as.integer(mam_par), FMM = 2L * as.integer(n_components))
  if (model != "FMM" && n <= n_par) {
    stop(model, " 적용에는 De가 ", n_par + 1L, "개 이상 필요합니다 (현재 ", n, "개).")
  }

  if (model %in% c("MAM", "FMM")) {
    if (is.null(sigmab) || !is.finite(sigmab) || sigmab <= 0 || sigmab >= 1) {
      stop(model, "에는 sigmab(0~1 사이 비율, 예: 0.2)가 필요합니다.")
    }
  }

  data <- data.frame(De = de, De.Error = de_error)

  dose <- NA_real_
  dose_error <- NA_real_
  extra <- list()

  if (model == "CAM") {
    s <- get_RLum(calc_CentralDose(data, verbose = FALSE, plot = FALSE), "summary")
    dose <- s$de
    dose_error <- s$de_err
    extra <- list(od_rel = as.numeric(s$rel_OD), od_rel_error = as.numeric(s$rel_OD_err))
  } else if (model == "MAM") {
    s <- get_RLum(
      calc_MinDose(data, sigmab = sigmab, log = TRUE, par = mam_par,
                   bootstrap = FALSE, plot = FALSE, verbose = FALSE),
      "summary"
    )
    dose <- s$de
    dose_error <- s$de_err
    extra <- list(mam_par = as.integer(mam_par), p0 = as.numeric(s$p0))
  } else {
    k <- as.integer(n_components)
    if (length(k) != 1 || is.na(k) || k < 2 || k > .fmm_max_k(n)) {
      stop("FMM(k=", k, ")에는 De가 ", 2L * k, "개 이상 필요합니다 (현재 ", n, "개).")
    }

    res <- calc_FiniteMixture(data, sigmab = sigmab, n.components = k,
                              verbose = FALSE, plot = FALSE)
    comp <- res@data$summary  # data.frame: de, de_err, proportion(0~1)

    # 미수렴/특이행렬이면 예외 대신 NA가 돌아온다. 조용히 넘기지 않는다.
    if (is.null(comp) || any(!is.finite(comp$de))) {
      stop("FMM(k=", k, ") 적합 결과가 유효하지 않습니다(미수렴·특이행렬 등).")
    }

    extra <- list(
      n_components = k,
      component_dose = as.numeric(comp$de),
      component_dose_error = as.numeric(comp$de_err),
      component_proportion = as.numeric(comp$proportion)
    )
  }

  c(
    list(
      model = model,
      n = as.integer(n),
      dose = as.numeric(dose),
      dose_error = as.numeric(dose_error),
      # CAM은 sigmab를 쓰지 않는다. 안 쓴 값을 기록하면 결과를 오해하게 된다.
      sigmab = if (model == "CAM" || is.null(sigmab)) NA_real_ else as.numeric(sigmab),
      package = "Luminescence",
      package_version = as.character(packageVersion("Luminescence"))
    ),
    extra
  )
}


# ④ 지표 -> FMM BIC -> 규칙 추천 -> 모델 적용.
# model을 주면 추천과 다른 모델을 적용하되, 무엇이 추천이었고 누가 골랐는지 함께 남긴다.
# FMM이 실패(표본 부족·미수렴)해도 멈추지 않는다: 추천 규칙은 "FMM 없음"을 처리한다.
run_age_model <- function(de, de_error, sigmab, model = NULL, max_k = 4L) {
  dist <- analyse_de_distribution(de, de_error)

  fmm <- tryCatch(fit_finite_mixture(de, de_error, sigmab = sigmab, max_k = max_k),
                  error = function(e) e)
  fmm_error <- NA_character_

  if (inherits(fmm, "error")) {
    fmm_error <- conditionMessage(fmm)
    fmm <- NULL
  } else if (!is.finite(fmm$delta_bic) || is.na(fmm$best_k)) {
    fmm_error <- "FMM 적합 결과가 유효하지 않습니다(특이행렬·미수렴 등)."
    fmm <- NULL
  }

  rec <- recommend_age_model(dist$od_rel, dist$skewness, dist$n, fmm)

  chosen <- if (is.null(model)) rec$model else model

  n_components <- NULL
  if (chosen == "FMM") {
    if (is.null(fmm)) {
      stop("FMM을 적용하려면 성분 수를 정할 BIC 비교가 필요한데 FMM 적합이 실패했습니다: ", fmm_error)
    }
    n_components <- fmm$best_k
  }

  applied <- apply_age_model(de, de_error, chosen, sigmab = sigmab, n_components = n_components)

  list(
    distribution = dist,
    fmm = fmm,
    fmm_error = fmm_error,
    recommendation = rec,
    model_source = if (is.null(model)) "rule" else "user",
    result = applied
  )
}
