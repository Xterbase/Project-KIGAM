<?php
// web/dashboard.php — 샘플 하나의 대시보드 화면 틀.
// 파일 구성(inspect.json)만 페이지에 싣고, 곡선·SAR·모델은 assets/app.js가 api.php로 그때그때 받는다.

declare(strict_types=1);

require __DIR__ . '/../php/bridge.php';

$id = (string) ($_GET['id'] ?? '');
$dir = sample_dir($id);
$meta = $dir ? read_json($dir . '/meta.json') : null;
$inspect = $dir ? read_json($dir . '/inspect.json') : null;
$error = null;

if ($meta === null || $inspect === null) {
    http_response_code(404);
    $error = '샘플을 찾을 수 없음.';
} elseif (!$inspect['ok']) {
    $error = '파일 읽기 실패: ' . $inspect['error'];
}
?>
<!doctype html>
<html lang="ko">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title><?= $meta ? h($meta['original_name']) . ' · ' : '' ?>Luminous</title>
<link rel="stylesheet" href="assets/app.css">
</head>
<body>
<?php if ($error): ?>
  <div class="page">
    <p class="axis">대시보드</p>
    <div class="card error"><?= h($error) ?></div>
    <a class="bracket" href="./">업로드로 돌아가기</a>
  </div>
<?php else: ?>
<div class="layout">
  <nav>
    <div class="brand">Luminous</div>
    <div class="file"><?= h($meta['original_name']) ?></div>
    <!-- 트리 메뉴: 선택한 탭은 흰 박스(pill)가 되어 오른쪽 내용 패널과 한 덩어리로 이어진다. 하위 항목은 선택한 탭에서만 펼침. -->
    <ul class="tree" id="tree">
      <li class="pill" id="pill" aria-hidden="true"></li>
      <li data-v="upload"><a class="tab" href="#upload"><span class="dot"></span>업로드<span class="num">01</span></a>
        <div class="sub"><ul><li><a href="#file">파일 구성</a></li><li><a href="#upfile">다른 파일 올리기</a></li><li><a href="#uplist">샘플 목록</a></li></ul></div></li>
      <li data-v="signal"><a class="tab" href="#signal"><span class="dot"></span>신호 분석<span class="num">02</span></a>
        <div class="sub"><ul><li><a href="#sigcurve">곡선 보기</a></li><li><a href="#sigrun">분석 조건 · SAR</a></li></ul></div></li>
      <li data-v="dash"><a class="tab" href="#dash"><span class="dot"></span>대시보드<span class="num">03</span></a>
        <div class="sub"><ul><li><a href="#dplots">그래프 4종</a></li><li><a href="#dmap">디스크 지도</a></li><li><a href="#dtable">단위별 결과</a></li><li><a href="#dqc">선택 단위 QC</a></li></ul></div></li>
      <li data-v="model"><a class="tab" href="#model"><span class="dot"></span>연령 모델<span class="num">04</span></a>
        <div class="sub"><ul><li><a href="#modelBox">추천 · 대표 선량</a></li></ul></div></li>
    </ul>
  </nav>

  <main class="panel">
    <div class="context" id="context"></div>

    <section class="view" id="upload">
      <p class="axis">01 · 업로드</p>
      <h2 id="file">파일 구성</h2>
      <div class="card facts" id="facts"></div>
      <h3>디스크 목록</h3>
      <div class="tablewrap"><table id="discs"></table></div>

      <h3 id="upfile">다른 파일 올리기</h3>
      <!-- 업로드 처리는 index.php가 한다(저장 → inspect → 새 대시보드로 이동). -->
      <form method="post" action="./" enctype="multipart/form-data" id="upForm">
        <label class="drop" id="drop">
          <input type="file" name="bin" accept=".bin,.BIN,.rda,.rdata,.RData" hidden>
          <b>BIN / RDA 파일을 끌어다 놓기</b><span class="note">또는 눌러서 선택 · 올리면 파일 구성을 읽고 새 대시보드로 이동(수 초 소요)</span>
        </label>
      </form>

      <h3 id="uplist">샘플 목록</h3>
      <?php sample_table(list_samples(), $id); ?>
    </section>

    <section class="view" id="signal">
      <p class="axis">02 · 신호 분석</p>
      <h2>신호 곡선과 분석 조건</h2>
      <div class="row" id="sigcurve">
        <label>디스크 <select id="selPos"></select></label>
        <label id="grainLabel">알갱이 <select id="selGrain"></select></label>
        <label>측정 <select id="selRec"></select></label>
      </div>
      <div class="howto"></div>
      <div class="plotbox"><div id="curvePlot" class="plot tall"></div></div>
      <p class="note" id="curveInfo"></p>

      <h3 id="sigrun">분석 조건</h3>
      <div class="card">
        <form id="runForm">
          <div class="row">
            <span class="seg" id="modeSeg"><span class="thumb"></span></span>
            <!-- 구간 = 시작 채널 : 끝 채널. ':'는 고정이고 숫자 두 칸만 입력한다. -->
            <label>신호 구간 <span class="range"><input type="number" id="sig1" min="1" placeholder="6" required><i>:</i><input type="number" id="sig2" min="1" placeholder="10" required></span></label>
            <label>배경 구간 <span class="range"><input type="number" id="bg1" min="1" placeholder="81" required><i>:</i><input type="number" id="bg2" min="1" placeholder="100" required></span></label>
          </div>
          <div class="row" style="margin:0">
            <button type="submit" class="btn primary" id="runBtn">SAR 실행</button>
            <span class="note" id="runStatus"></span>
          </div>
        </form>
        <p class="note" id="runHint" style="margin:10px 0 0"></p>
      </div>
    </section>

    <section class="view" id="dash">
      <p class="axis">03 · 대시보드</p>
      <h2>De 분포 대시보드</h2>
      <p class="note" id="distEmpty">SAR 실행 대기. 02 · 신호 분석에서 적분 구간을 정하고 실행하면 표시됨.</p>
      <div id="distBody" hidden>
        <div class="selbar">
          <button class="btn" id="prevBtn" title="이전 (←)">이전</button>
          <span class="big" id="selTitle"></span>
          <span id="selDetail"></span>
          <button class="btn" id="nextBtn" title="다음 (→)">다음</button>
          <span class="note">표·지도를 누르거나 ← → 키로 이동</span>
        </div>
        <div class="howto"></div>
        <div class="dash" id="dplots">
          <div class="plotbox"><div id="dCurve" class="plot"></div></div>
          <div class="plotbox"><div id="dDR" class="plot"></div></div>
          <div class="plotbox"><div id="dHist" class="plot"></div></div>
          <div class="plotbox"><div id="dRadial" class="plot"></div></div>
        </div>
        <p class="note">방사형 그래프: QC 통과 De만 표시. De는 원점(왼쪽 0)에서 점을 지나는 직선을 오른쪽 호까지 연장해 읽음. 회색 띠(±2) 안이면 자기 오차 범위에서 중심값과 같음.</p>
        <div class="lower">
          <div id="dmap">
            <div class="row"><b id="mapTitle"></b> <select id="mapDisc"></select></div>
            <div class="map" id="map"></div>
            <div class="legend"><span><i style="background:var(--pass)"></i>통과</span><span><i style="background:var(--fail)"></i>탈락</span>
              <span><i style="box-shadow:inset 0 0 0 0.5px var(--slate-smoke)"></i>파일에 없음</span></div>
            <p class="note" id="mapNote"></p>
          </div>
          <div>
            <div class="row" id="dtable"><b>분석 단위별 결과</b>
              <label class="switch"><input type="checkbox" id="onlyPass"><span class="track"><span class="knob"></span></span>통과만 보기</label>
              <span class="note" id="tableCount"></span></div>
            <div class="tablewrap"><table id="units"></table></div>
            <p class="note" id="failedNote"></p>
            <h3 id="dqc">선택한 단위의 QC</h3>
            <div class="tablewrap"><table id="qc"></table></div>
          </div>
        </div>
      </div>
    </section>

    <section class="view" id="model">
      <p class="axis">04 · 연령 모델</p>
      <h2>연령 모델</h2>
      <div class="card" id="modelBox"><p class="note">SAR 실행 대기.</p></div>
    </section>
  </main>
</div>
<div class="chip" id="chip"></div>

<script id="boot" type="application/json"><?= json_encode(
    ['id' => $id, 'file' => $meta['original_name'], 'inspect' => $inspect['result'], 'meta' => $inspect['meta']],
    JSON_UNESCAPED_UNICODE | JSON_HEX_TAG | JSON_HEX_AMP
) ?></script>
<script src="assets/vendor/plotly-basic-2.35.2.min.js"></script>
<script src="assets/drop.js"></script>
<script src="assets/app.js"></script>
<?php endif; ?>
</body>
</html>
