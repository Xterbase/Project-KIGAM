# R/run.R — 웹 계층(PHP)이 부르는 진입점.
#
#   Rscript R/run.R <input.json> <output.json>
#
# 입력: {"action": "<동작>", "args": {...}}
# 출력: {"ok": true,  "action": ..., "result": {...}, "meta": {...}}
#       {"ok": false, "action": ..., "error": "<메시지>", "meta": {...}}
# 종료 코드: 성공 0, 실패 1. 출력 파일은 실패해도 쓴다(PHP가 에러 메시지를 읽는다).
#
# JSON 규칙(브라우저가 그대로 믿을 수 있게):
#   - 배열 필드는 원소가 1개여도 배열이다(I()로 표시). 스칼라는 스칼라다.
#   - 표는 행 객체의 배열이다: [{"position": 1, "de": ...}, ...]
#   - NA / NaN / Inf는 null이다. 숫자는 반올림하지 않는다(digits = NA).
#
# 동작(args):
#   inspect        path
#   curve          path, position, record_index, grain?, mode?
#   sar            path, positions, signal_integral, background_integral, mode?, seed?, progress_file?
#   dose_response  path, position, signal_integral, background_integral, grain?, mode?, seed?
#   age_model      de, de_error, sigmab, model?, max_k?
#
# 사용자 입력은 PHP가 셸 문자열에 끼워 넣지 말고 이 JSON 파일로만 넘긴다.

script_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
here <- dirname(normalizePath(sub("^--file=", "", script_arg)))

suppressPackageStartupMessages({
  source(file.path(here, "Analysis.R"))
  library(jsonlite)
})

.arr <- function(x) I(x)

.opt <- function(args, name, default = NULL) {
  if (is.null(args[[name]])) default else args[[name]]
}

.ACTIONS <- list(
  inspect = function(a) {
    info <- inspect_positions(a$path)
    meta <- load_bin_data(a$path)$metadata

    # record_index = 분석 단위(POSITION, single-grain이면 +GRAIN) 안에서의 순번.
    # .position_records()가 metadata 순서로 record를 꺼내므로 같은 번호 체계다.
    unit_key <- paste(meta$POSITION, meta$GRAIN)
    record_index <- ave(seq_len(nrow(meta)), unit_key, FUN = seq_along)

    cols <- intersect(
      c("ID", "POSITION", "GRAIN", "RUN", "SET", "LTYPE", "DTYPE", "IRR_TIME", "NPOINTS",
        "LOW", "HIGH", "TEMPERATURE", "AN_TEMP", "AN_TIME", "LIGHTSOURCE", "SAMPLE", "COMMENT"),
      colnames(meta)
    )
    records <- data.frame(record_index = record_index, meta[, cols, drop = FALSE])
    names(records) <- tolower(names(records))

    list(
      file = info$file,
      file_type = info$file_type,
      object_name = info$object_name,
      ignored_objects = .arr(info$ignored_objects),
      single_grain = info$single_grain,
      n_positions = info$n_positions,
      positions = .arr(info$positions),
      grains = data.frame(position = info$grain_position, grain = info$grain),
      record_types = .arr(info$record_types),
      records = records
    )
  },

  curve = function(a) {
    r <- get_record_curve(a$path, a$position, a$record_index, grain = .opt(a, "grain"), mode = .opt(a, "mode"))
    r$x <- .arr(r$x)
    r$y <- .arr(r$y)
    r
  },

  sar = function(a) {
    s <- run_sar_analysis(
      a$path, a$positions, a$signal_integral, a$background_integral,
      mode = .opt(a, "mode", "single_aliquot"),
      seed = .opt(a, "seed", 1L),
      progress_file = .opt(a, "progress_file")
    )

    list(
      mode = s$mode,
      seed = s$seed,
      signal_integral = .arr(s$signal_integral),
      background_integral = .arr(s$background_integral),
      n_requested = s$n_requested,
      n_success = s$n_success,
      n_failed = s$n_failed,
      units = data.frame(
        position = s$position, grain = s$grain, de = s$de, de_error = s$de_error,
        rc_status = s$rc_status, fit = s$fit, recycling_ratio = s$recycling_ratio,
        recuperation = s$recuperation, warning = s$warning
      ),
      qc = data.frame(
        position = s$qc_position, grain = s$qc_grain, criteria = s$qc_criteria,
        value = s$qc_value, threshold = s$qc_threshold, status = s$qc_status
      ),
      failed = data.frame(position = s$failed_position, grain = s$failed_grain, reason = s$failed_reason),
      discs = data.frame(position = s$disc_position, n_units = s$disc_n_units, n_accepted = s$disc_n_accepted)
    )
  },

  dose_response = function(a) {
    d <- get_dose_response(
      a$path, a$position, a$signal_integral, a$background_integral,
      grain = .opt(a, "grain"),
      mode = .opt(a, "mode", "single_aliquot"),
      seed = .opt(a, "seed", 1L)
    )
    d$signal_integral <- .arr(d$signal_integral)
    d$background_integral <- .arr(d$background_integral)
    d$curve_x <- .arr(d$curve_x)
    d$curve_y <- .arr(d$curve_y)
    d
  },

  age_model = function(a) {
    r <- run_age_model(a$de, a$de_error, sigmab = a$sigmab,
                       model = .opt(a, "model"), max_k = .opt(a, "max_k", 4L))
    d <- r$distribution
    res <- r$result
    rec <- r$recommendation

    fmm <- NULL
    if (!is.null(r$fmm)) {
      fmm <- list(sigmab = r$fmm$sigmab, single_bic = r$fmm$single_bic,
                  bic = data.frame(k = r$fmm$k, bic = r$fmm$bic),
                  best_k = r$fmm$best_k, delta_bic = r$fmm$delta_bic)
    }

    if (res$model == "FMM") {
      res$components <- data.frame(dose = res$component_dose, dose_error = res$component_dose_error,
                                   proportion = res$component_proportion)
      res$component_dose <- res$component_dose_error <- res$component_proportion <- NULL
    }

    rec$reasons <- .arr(rec$reasons)

    list(
      distribution = list(
        n = d$n, n_dropped = d$n_dropped,
        central_de = d$central_de, central_de_error = d$central_de_error,
        od_rel = d$od_rel, od_rel_error = d$od_rel_error,
        skewness = d$skewness, kurtosis = d$kurtosis,
        mean_de = d$mean_de, median_de = d$median_de, sd_rel = d$sd_rel,
        points = data.frame(de = d$de, de_error = d$de_error, radial_x = d$radial_x, radial_y = d$radial_y)
      ),
      fmm = fmm,
      fmm_error = r$fmm_error,
      recommendation = rec,
      model_source = r$model_source,
      result = res
    )
  }
)

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2) {
  stop("사용법: Rscript R/run.R <input.json> <output.json>")
}

input <- tryCatch(fromJSON(args[1], simplifyVector = TRUE), error = function(e) e)
action <- if (is.list(input) && !inherits(input, "error")) input$action else NA_character_

out <- tryCatch({
  if (inherits(input, "error")) stop("입력 JSON을 읽지 못했습니다: ", conditionMessage(input))
  if (is.null(action) || !(action %in% names(.ACTIONS))) {
    stop("알 수 없는 동작입니다: ", format(action), " / 가능: ", paste(names(.ACTIONS), collapse = ", "))
  }
  list(ok = TRUE, action = action, result = .ACTIONS[[action]](input$args))
}, error = function(e) {
  list(ok = FALSE, action = if (is.null(action)) NA_character_ else action, error = conditionMessage(e))
})

out$meta <- list(
  r_version = paste(R.version$major, R.version$minor, sep = "."),
  luminescence_version = as.character(packageVersion("Luminescence"))
)

# 임시 파일에 쓰고 rename: PHP가 반쯤 쓰인 파일을 읽지 않게 한다.
tmp <- paste0(args[2], ".tmp")
write_json(out, tmp, auto_unbox = TRUE, digits = NA, na = "null", null = "null", pretty = FALSE)
invisible(file.rename(tmp, args[2]))

quit(status = if (isTRUE(out$ok)) 0L else 1L, save = "no")
