# R/02_signal.R — ② 신호: 선택한 POSITION의 RLum record 목록과 신호 곡선.
# 연구자가 곡선을 보고 signal/background integral을 정하는 단계다.
#
#   get_record_curve() : record 하나의 곡선을 그래프용 데이터로 반환(브라우저가 그림)
#
# OSLdecomposition(조건부 도입)은 이 단계와 ③ SAR 사이에 들어간다.
# ---------------------------
# 선택한 POSITION(+GRAIN)의 metadata row와 RLum record를 함께 가져오고,
# 둘의 1:1 정렬이 실제로 성립하는지 검증한다.
#
# 배경 (중요):
#   record_index는 "metadata 행 순서 == RLum record 순서"라는 전제로 만들어지고,
#   get_record_curve()는 그 번호로 record를 꺼낸다.
#   이 전제가 깨지면 사용자가 고른 record와 다른 곡선이 에러 없이 그려진다.
#
#   Risoe.BINfileData2RLum.Analysis()는 GRAIN 값별로 결과를 만들기 때문에,
#   한 POSITION에 GRAIN이 여러 개면(single-grain) pos만 주었을 때
#   "grain별 RLum.Analysis의 list"를 반환하고, obj[record_index]는 grain을 가리키게 된다.
#   그래서 single-grain 파일은 grain을 반드시 지정해 grain 하나의 record만 꺼낸다.
#   grain 없이 여러 GRAIN이 있는 POSITION을 요청하면 틀린 곡선 대신 명시적으로 막는다.
#
# bin_data를 직접 받는 이유: single-aliquot 모드는 파일이 아니라 convert_SG2MG()로
# 변환한 객체에서 record를 꺼내야 한다.

.position_records <- function(bin_data, pos, grain = NULL) {   # position(+grain)의 record를 꺼내고 정렬이 맞는지 검증
  metadata <- bin_data@METADATA

  pos <- as.integer(pos)
  in_pos <- metadata$POSITION == pos

  if (!any(in_pos)) {
    stop(paste0("해당 POSITION의 metadata를 찾지 못했습니다: ", pos))
  }

  grains <- sort(unique(metadata$GRAIN[in_pos]))
  grains <- grains[!is.na(grains)]  #GRAIN이 비어있는 행을 대비한 방어코드

  if (is.null(grain)) {
    if (length(grains) > 1) {
      stop(
        paste0(
          "POSITION ", pos, "에 GRAIN이 여러 개 있습니다 (",
          paste(grains, collapse = ", "),
          "). single-grain 파일은 GRAIN을 지정해야 합니다. ",
          "지정하지 않으면 record 번호와 실제 곡선이 어긋납니다."
        )
      )
    }
# position에 grain이 2개 이상이면 즉시 stop(). grain을 지정하지 않으면 record_index와 실제 곡선이 어긋나기때문.
    metadata_index <- which(in_pos)
    obj <- Risoe.BINfileData2RLum.Analysis(object = bin_data, pos = pos)
  } else {
    grain <- as.integer(grain)

    if (!(grain %in% grains)) {
      stop(paste0("POSITION ", pos, "에 GRAIN ", grain, "이(가) 없습니다."))
    }

    metadata_index <- which(in_pos & metadata$GRAIN == grain)
    obj <- Risoe.BINfileData2RLum.Analysis(object = bin_data, pos = pos, grain = grain)
  }

  meta_pos <- metadata[metadata_index, , drop = FALSE]
  label <- if (is.null(grain)) paste0("POSITION ", pos) else paste0("POSITION ", pos, " GRAIN ", grain)


## 최종검증: metadata 행 순서와 RLum record 순서가 1:1로 맞는지 확인.
# (1) 반환값이 list가 아니라 Rlum.Analysis 하나인지,
# (2) metadata_index와 obj 길이가 같은지 확인.(=표의 행 순서와 RLum record 순서가 1:1로 맞는지 확인)
  if (length(obj) == 0) {
    stop(paste0(label, "의 RLum record를 찾지 못했습니다."))
  }

  # 개수가 안 맞으면 정렬을 신뢰할 수 없다.
  if (!inherits(obj, "RLum.Analysis") || nrow(meta_pos) != length(obj)) {
    stop(
      paste0(
        label, "의 record 정렬이 맞지 않습니다: ",
        "METADATA record ", nrow(meta_pos), "개, ",
        "RLum record ", length(obj), "개. ",
        "record 번호와 실제 곡선이 어긋날 수 있어 분석을 중단합니다."
      )
    )
  }

  list(
    pos = pos,
    grain = if (is.null(grain)) NA_integer_ else grain,
    obj = obj,
    meta_pos = meta_pos,
    metadata_index = metadata_index
  )
}

.load_position_records <- function(path, pos, grain = NULL) {  #경로를 받아 .position_records()를 호출(bin_data 캐시).
  .position_records(load_bin_data(path)$bin_data, pos, grain)
}





# record 하나의 곡선을 그래프용 데이터로 반환한다(브라우저가 그린다).
# 하나의 곡선 x,y를 브라우저용으로 반환.
# x는 OSL/IRSL이면 자극 시간(s), TL이면 온도(°C)다. record_type으로 구분한다.
get_record_curve <- function(path, pos, record_index, grain = NULL) {
  found <- .load_position_records(path, pos, grain)
  record_index <- as.integer(record_index)

  if (record_index < 1 || record_index > length(found$obj)) {
    stop("존재하지 않는 record index입니다: ", record_index, " / 가능한 범위: 1:", length(found$obj))
  }

  curve <- get_RLum(found$obj, record.id = record_index)
  xy <- get_RLum(curve)

  list(
    position = found$pos,
    grain = as.integer(found$grain),
    record_index = record_index,
    record_type = as.character(curve@recordType),
    x = as.numeric(xy[, 1]),
    y = as.numeric(xy[, 2])
  )
}
