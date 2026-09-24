# R/01_load.R — ① 로드: 파일 경로 -> Risoe.BINfileData.
# 모든 단계가 공유하는 파일 캐시와 PNG 저장 헬퍼도 여기 둔다.

# ============================================================
# Common: 로드된 파일 캐시
# ============================================================
# load_bin_data()는 inspect_positions / inspect_rlum_records_by_position /
# save_rlum_record_plot 등 모든 진입점의 첫 줄에서 호출된다.
# 캐시가 없으면 record를 하나 클릭할 때마다 BIN 파일 전체를 다시 파싱하므로,
# 실제 크기의 측정 파일에서는 클릭마다 수 초씩 멈춘다.
#
# 캐시 키 = 정규화 경로 + mtime + size
#   → 같은 경로라도 파일 내용이 바뀌면 키가 달라져 자동으로 무효화된다.
#
# Risoe.BINfileData 객체는 메모리를 많이 쓰므로 최근 N개만 유지한다(LRU).

.bin_cache <- new.env(parent = emptyenv())
.BIN_CACHE_MAX_ENTRIES <- 3L

.bin_cache_key <- function(normalized_path) {
  info <- file.info(normalized_path)

  paste(
    normalized_path,
    as.numeric(info$mtime),
    info$size,
    sep = "|"
  )
}

.bin_cache_get <- function(key) {
  if (!exists(key, envir = .bin_cache, inherits = FALSE)) {
    return(NULL)
  }

  entry <- get(key, envir = .bin_cache, inherits = FALSE)

  # LRU(Least Recently Used, 가장 최근에 사용되지 않은 것) 갱신
  entry$last_used <- Sys.time()
  assign(key, entry, envir = .bin_cache)

  entry$value
}

.bin_cache_put <- function(key, value) {  # key(경로+mtime+size)를 기준으로 value와 last_used를 .bin_cache에 저장한다. LRU 정책으로 오래된 캐시는 제거.
  assign(
    key,
    list(value = value, last_used = Sys.time()),
    envir = .bin_cache
  )

  keys <- ls(.bin_cache, all.names = TRUE)

  if (length(keys) > .BIN_CACHE_MAX_ENTRIES) {
    last_used <- vapply(
      keys,
      function(k) as.numeric(get(k, envir = .bin_cache)$last_used),
      numeric(1)
    )

    n_drop <- length(keys) - .BIN_CACHE_MAX_ENTRIES
    drop_keys <- keys[order(last_used)][seq_len(n_drop)]

    rm(list = drop_keys, envir = .bin_cache)
  }

  invisible(value)
}

clear_bin_cache <- function() {
  rm(
    list = ls(.bin_cache, all.names = TRUE),
    envir = .bin_cache
  )

  invisible(TRUE)
}

# ============================================================
# Common: data loading
# ============================================================
# BIN/RDA/RData 파일을 읽고, 이후 분석 단계에서 공통으로 사용할
# Risoe.BINfileData 객체와 metadata 정보를 반환한다.

load_bin_data <- function(path) {
  # ------------------------------------------------------------
  # 1. path 입력 검증
  # ------------------------------------------------------------
  if (missing(path) || is.null(path) || length(path) != 1 || !nzchar(path)) {
    stop("파일 경로가 비어 있거나 올바르지 않습니다.")
  }

  path <- as.character(path)

  # ------------------------------------------------------------
  # 2. 파일 존재 여부 검증
  # ------------------------------------------------------------
  if (!file.exists(path)) {
    stop(paste0("파일을 찾을 수 없습니다: ", path))
  }

  # ------------------------------------------------------------
  # 3. 경로 정규화
  #    - Python/Streamlit/SQL/JSON 저장 시 경로 일관성 확보
  # ------------------------------------------------------------
  normalized_path <- normalizePath(
    path,
    winslash = "/",
    mustWork = TRUE
  )

  file_name <- basename(normalized_path)
  ext <- tolower(tools::file_ext(normalized_path))

  # ------------------------------------------------------------
  # 3-1. 캐시 조회
  #      같은 파일(경로+mtime+size)이면 재파싱하지 않는다.
  # ------------------------------------------------------------
  cache_key <- .bin_cache_key(normalized_path)
  cached <- .bin_cache_get(cache_key)

  if (!is.null(cached)) {
    return(cached)
  }

  # ------------------------------------------------------------
  # 4. 확장자 검증
  # ------------------------------------------------------------
  supported_ext <- c("bin", "rda", "rdata")

  if (!(ext %in% supported_ext)) {
    stop(
      paste0(
        "지원하지 않는 파일 형식입니다: ",
        ext,
        " / 지원 형식: ",
        paste(supported_ext, collapse = ", ")
      )
    )
  }

  object_name <- NA_character_
  bin_data <- NULL

  # rda/RData는 객체를 여러 개 담을 수 있다. 몇 개 중에 뭘 골랐는지를
  # 호출부(UI)까지 올려보내기 위한 값. bin은 객체 하나짜리 형식이라 1로 고정.
  n_candidates <- 1L
  ignored_objects <- character(0)

  # ------------------------------------------------------------
  # 5. BIN 파일 로딩
  # ------------------------------------------------------------
  if (ext == "bin") {
    bin_data <- read_BIN2R(
      file = normalized_path,
      verbose = FALSE
    )

    object_name <- "read_BIN2R_result"
  }

  # ------------------------------------------------------------
  # 6. RDA/RData 파일 로딩
  #    - 별도 environment에 load해서 현재 환경 오염 방지
  # ------------------------------------------------------------
  else if (ext %in% c("rda", "rdata")) {
    load_env <- new.env(parent = emptyenv())

    loaded_names <- load(
      file = normalized_path,
      envir = load_env
    )

    if (length(loaded_names) == 0) {
      stop("RDA/RData 파일 안에 로드된 객체가 없습니다.")
    }

    candidates <- loaded_names[
      sapply(loaded_names, function(name) {
        obj <- get(name, envir = load_env)
        inherits(obj, "Risoe.BINfileData")
      })
    ]

    if (length(candidates) == 0) {
      stop("RDA/RData 파일 안에서 Risoe.BINfileData 객체를 찾지 못했습니다.")
    }

    # 후보가 여러 개면 첫 번째를 쓰되, 여기서 조용히 넘어가면 안 된다.
    # load()가 돌려주는 순서 = 저장 당시 인자 순서라서, 어느 시료가
    # 분석될지가 연구자에게 보이지 않는 요인으로 결정된다.
    # 몇 개 중 뭘 골랐고 뭘 버렸는지를 반환값에 실어 UI에서 경고한다.
    n_candidates <- length(candidates)
    object_name <- candidates[1]
    ignored_objects <- candidates[-1]

    bin_data <- get(object_name, envir = load_env)
  }

  # ------------------------------------------------------------
  # 7. 최종 객체 타입 검증
  # ------------------------------------------------------------
  if (!inherits(bin_data, "Risoe.BINfileData")) {
    stop("불러온 객체가 Risoe.BINfileData 형식이 아닙니다.")
  }

  # ------------------------------------------------------------
  # 8. METADATA 검증
  # ------------------------------------------------------------
  if (is.null(bin_data@METADATA)) {
    stop("Risoe.BINfileData 객체에 METADATA 슬롯이 없습니다.")
  }

  if (nrow(bin_data@METADATA) == 0) {
    stop("Risoe.BINfileData 객체의 METADATA가 비어 있습니다.")
  }

  metadata <- bin_data@METADATA
  metadata_columns <- colnames(metadata)

  # ------------------------------------------------------------
  # 9. POSITION 컬럼 검증
  # ------------------------------------------------------------
  if (!"POSITION" %in% metadata_columns) {
    stop("METADATA에서 POSITION 컬럼을 찾지 못했습니다.")
  }

  positions <- sort(unique(metadata$POSITION))
  positions <- positions[!is.na(positions)]

  if (length(positions) == 0) {
    stop("POSITION 정보를 찾지 못했습니다.")
  }

  # ------------------------------------------------------------
  # 10. 기본 record type 요약
  # ------------------------------------------------------------
  record_types <- character(0)

  if ("LTYPE" %in% metadata_columns) {
    record_types <- sort(unique(as.character(metadata$LTYPE)))
    record_types <- record_types[!is.na(record_types)]
  }

  # ------------------------------------------------------------
  # 11. 측정 방식 판별: GRAIN 번호가 기록돼 있으면 single-grain 파일이다.
  #     single-aliquot 파일은 GRAIN이 0이다. (POSITION, GRAIN) 쌍 = grain 하나.
  # ------------------------------------------------------------
  grain_pairs <- data.frame(POSITION = integer(0), GRAIN = integer(0))

  if ("GRAIN" %in% metadata_columns) {
    grain_pairs <- unique(metadata[!is.na(metadata$GRAIN), c("POSITION", "GRAIN")])
    grain_pairs <- grain_pairs[order(grain_pairs$POSITION, grain_pairs$GRAIN), ]
  }

  single_grain <- any(grain_pairs$GRAIN > 0)

  # ------------------------------------------------------------
  # 12. 반환 (캐시에 적재 후 반환)
  # ------------------------------------------------------------
  result <- list(
    bin_data = bin_data,
    metadata = metadata,

    file_path = normalized_path,
    file_name = file_name,
    file_type = ext,

    object_name = object_name,
    n_candidates = as.integer(n_candidates),
    ignored_objects = as.character(ignored_objects),

    n_metadata_rows = as.integer(nrow(metadata)),
    metadata_columns = as.character(metadata_columns),

    n_positions = as.integer(length(positions)),
    positions = as.integer(positions),

    single_grain = single_grain,
    grain_position = as.integer(grain_pairs$POSITION),
    grain = as.integer(grain_pairs$GRAIN),

    record_types = as.character(record_types)
  )

  .bin_cache_put(cache_key, result)

  result
}

# ============================================================
# Common: PNG 저장
# ============================================================
# plot 하나를 PNG로 저장하고 정규화 경로를 돌려준다.
# macOS quartz png는 dev.off() 시점에야 파일을 디스크에 쓴다. dev.off()를 on.exit에만
# 걸어두면 파일이 아직 없는 상태에서 존재 확인이 실패한다.
# -> draw() 직후 명시적으로 닫아 flush 하고, on.exit은 에러 시 device 누수 방지용으로만 둔다.

.save_png <- function(file_path, draw, width, height, res, label) {
  png(filename = file_path, width = width, height = height, res = res)

  device_id <- dev.cur()
  on.exit(
    if (dev.cur() == device_id) dev.off(),
    add = TRUE
  )

  draw()

  dev.off()

  if (!file.exists(file_path)) {
    stop(paste0(label, " 이미지를 생성하지 못했습니다: ", file_path))
  }

  normalizePath(file_path, winslash = "/", mustWork = TRUE)
}

# ============================================================
# POSITION 요약
# ============================================================
# load_bin_data()로 불러온 데이터에서 파일 구조, metadata, POSITION 목록을 요약한다.

inspect_positions <- function(path) {
  loaded <- load_bin_data(path)

  list(
    file = loaded$file_name,
    file_path = loaded$file_path,
    file_type = loaded$file_type,
    object_name = loaded$object_name,
    n_candidates = loaded$n_candidates,
    ignored_objects = loaded$ignored_objects,

    n_metadata_rows = loaded$n_metadata_rows,
    metadata_columns = loaded$metadata_columns,

    n_positions = loaded$n_positions,
    positions = loaded$positions,

    single_grain = loaded$single_grain,
    grain_position = loaded$grain_position,
    grain = loaded$grain,

    record_types = loaded$record_types
  )
}
