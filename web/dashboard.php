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
    <ol>
      <li><a href="#file">파일<small>디스크·알갱이 구성</small></a></li>
      <li><a href="#signal">신호<small>곡선 · 분석 조건</small></a></li>
      <li><a href="#dist">De 분포<small>한눈에 보는 대시보드</small></a></li>
      <li><a href="#model">모델<small>추천 · 대표 선량</small></a></li>
    </ol>
    <a class="bracket" href="./">다른 파일 올리기</a>
  </nav>

  <main>
    <div class="context" id="context"></div>

    <section id="file">
      <p class="axis">01 · 파일</p>
      <h2>파일 구성</h2>
      <div class="card facts" id="facts"></div>
      <h3>디스크 목록</h3>
      <div class="tablewrap"><table id="discs"></table></div>
    </section>

    <section id="signal">
      <p class="axis">02 · 신호</p>
      <h2>신호 곡선</h2>
      <div class="row">
        <label>디스크 <select id="selPos"></select></label>
        <label id="grainLabel">알갱이 <select id="selGrain"></select></label>
        <label>측정 <select id="selRec"></select></label>
      </div>
      <div class="plotbox"><div id="curvePlot" class="plot tall"></div></div>
      <p class="note" id="curveInfo"></p>

      <div class="card" style="margin-top:24px">
        <h3 style="margin-top:0">분석 조건</h3>
        <form id="runForm" class="row" style="margin-bottom:8px">
          <span class="seg" id="modeSeg"></span>
          <label>신호 구간 <input type="text" id="sig" placeholder="예: 6:10" pattern="\s*\d+\s*:\s*\d+\s*" required></label>
          <label>배경 구간 <input type="text" id="bg" placeholder="예: 81:100" pattern="\s*\d+\s*:\s*\d+\s*" required></label>
          <button type="submit" class="primary" id="runBtn">SAR 실행</button>
          <span class="note" id="runStatus"></span>
        </form>
        <p class="note" id="runHint"></p>
      </div>
    </section>

    <section id="dist">
      <p class="axis">03 · De 분포</p>
      <h2>De 분포 대시보드</h2>
      <p class="note" id="distEmpty">SAR 실행 대기. 02 · 신호에서 적분 구간을 정하고 실행하면 표시됨.</p>
      <div id="distBody" hidden>
        <div class="card selbar">
          <button id="prevBtn" title="이전 (←)">이전</button>
          <span class="big" id="selTitle"></span>
          <span id="selDetail"></span>
          <button id="nextBtn" title="다음 (→)">다음</button>
          <span class="note">표·지도를 누르거나 ← → 키로 이동</span>
        </div>
        <div class="dash">
          <div class="plotbox"><div id="dCurve" class="plot"></div></div>
          <div class="plotbox"><div id="dDR" class="plot"></div></div>
          <div class="plotbox"><div id="dHist" class="plot"></div></div>
          <div class="plotbox"><div id="dRadial" class="plot"></div>
            <p class="note">QC 통과 De만 표시. De는 원점(왼쪽 0)에서 점을 지나는 직선을 오른쪽 호까지 연장해 읽음. 회색 띠(±2) 안이면 자기 오차 범위에서 중심값과 같음.</p></div>
        </div>
        <div class="lower">
          <div>
            <div class="row"><b id="mapTitle"></b> <select id="mapDisc"></select></div>
            <div class="map" id="map"></div>
            <div class="legend"><span><i style="background:var(--pass)"></i>통과</span><span><i style="background:var(--fail)"></i>탈락</span>
              <span><i style="box-shadow:inset 0 0 0 0.5px var(--slate-smoke)"></i>파일에 없음</span></div>
            <p class="note" id="mapNote"></p>
          </div>
          <div>
            <div class="row"><b>분석 단위별 결과</b> <label class="note"><input type="checkbox" id="onlyPass"> 통과만 보기</label>
              <span class="note" id="tableCount"></span></div>
            <div class="tablewrap"><table id="units"></table></div>
            <p class="note" id="failedNote"></p>
            <h3>선택한 단위의 QC</h3>
            <div class="tablewrap"><table id="qc"></table></div>
          </div>
        </div>
      </div>
    </section>

    <section id="model">
      <p class="axis">04 · 모델</p>
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
<script src="assets/app.js"></script>
<?php endif; ?>
</body>
</html>
