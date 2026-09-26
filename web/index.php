<?php
// web/index.php — 업로드 + 샘플 목록.
// BIN/RDA 업로드 → outputs/samples/{id}/raw/ 저장 → R(run.R inspect) → dashboard.php로 이동.
//
// 로컬 실행: php -S localhost:8000 -t web -d upload_max_filesize=200M -d post_max_size=200M
// 서버: DocumentRoot는 web/만 지정한다. php.ini의 upload_max_filesize / post_max_size와
// nginx의 client_max_body_size(기본 1MB)를 실제 파일 크기에 맞게 올린다.

declare(strict_types=1);

require __DIR__ . '/../php/bridge.php';

$error = null;

// ---- 업로드 (POST) → 저장 → inspect → 대시보드로 이동 (POST-Redirect-GET)
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $f = $_FILES['bin'] ?? null;
    $ext = strtolower(pathinfo((string) ($f['name'] ?? ''), PATHINFO_EXTENSION));

    if (!$f || $f['error'] !== UPLOAD_ERR_OK) {
        $error = '업로드 실패(코드 ' . ($f['error'] ?? '없음') . '). 파일이 크면 upload_max_filesize 확인 필요.';
    } elseif (!in_array($ext, ALLOWED_EXT, true)) {
        $error = '지원하지 않는 형식: ' . $ext . ' (가능: ' . implode(', ', ALLOWED_EXT) . ')';
    } else {
        $id = date('Ymd-His') . '-' . bin2hex(random_bytes(3));
        $dir = sample_dir($id);

        // 서버에서 가장 흔한 실패: 웹 서버 계정이 outputs/에 쓸 권한이 없음.
        if (!@mkdir($dir . '/raw', 0775, true)) {
            $error = '샘플 폴더를 만들지 못함. 웹 서버 계정의 outputs/ 쓰기 권한 확인 필요.';
        } else {
            // 저장 이름은 서버가 정한다. 원래 파일명은 기록만 한다.
            $path = $dir . '/raw/input.' . $ext;
            move_uploaded_file($f['tmp_name'], $path);

            $r = run_r('inspect', ['path' => $path], $dir, 'inspect.json');
            $x = $r['result'] ?? [];
            file_put_contents($dir . '/meta.json', json_encode([
                'original_name' => $f['name'],
                'uploaded_at' => date('c'),
                'size' => $f['size'],
                // 목록 표시용 요약(inspect.json 전체를 매번 읽지 않도록)
                'ok' => $r['ok'],
                'single_grain' => $x['single_grain'] ?? null,
                'n_positions' => $x['n_positions'] ?? null,
                'n_grains' => isset($x['grains']) ? count($x['grains']) : null,
                'n_records' => isset($x['records']) ? count($x['records']) : null,
                'record_types' => $x['record_types'] ?? null,
                'header' => $x['header'] ?? null,
            ], JSON_UNESCAPED_UNICODE));

            header('Location: dashboard.php?id=' . $id);
            exit;
        }
    }
}

$samples = list_samples();
?>
<!doctype html>
<html lang="ko">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Luminous</title>
<link rel="stylesheet" href="assets/app.css">
</head>
<body>
<div class="page">
  <p class="axis">00 · 업로드</p>
  <h1>Luminous</h1>
  <p class="lead">루미네선스 측정 파일(BIN/RDA)을 올리면 신호 곡선, SAR, De 분포, 연령 모델을 한 화면에서 확인함.</p>

  <?php if ($error): ?>
    <div class="card error"><?= h($error) ?></div>
  <?php endif; ?>

  <!-- 끌어다 놓기 영역(assets/drop.js): 파일을 고르는 즉시 올리고 대시보드로 이동 -->
  <form method="post" enctype="multipart/form-data" id="upForm">
    <label class="drop" id="drop">
      <input type="file" name="bin" accept=".bin,.BIN,.rda,.rdata,.RData" hidden>
      <b>BIN / RDA 파일을 끌어다 놓기</b>
      <span class="note">또는 눌러서 선택 · 최대 <?= h(ini_get('upload_max_filesize')) ?> · 올리면 파일 구성을 읽고 대시보드로 이동(수 초 소요)</span>
    </label>
  </form>

  <p class="axis" style="margin-top:48px">샘플 목록</p>
  <?php if (!$samples): ?>
    <p class="note">아직 올린 파일 없음.</p>
  <?php else: ?>
    <?php sample_table($samples); ?>
  <?php endif; ?>
</div>
<script src="assets/drop.js"></script>
</body>
</html>
