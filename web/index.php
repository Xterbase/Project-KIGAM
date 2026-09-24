<?php
// web/index.php — 0단계: BIN 업로드 → R(run.R inspect) → 디스크 목록 표.
//
// 로컬 실행: php -S localhost:8000 -t web -d upload_max_filesize=200M -d post_max_size=200M
// 서버: php.ini의 upload_max_filesize / post_max_size를 실제 파일 크기에 맞게 올린다.
// Rscript 경로가 PATH에 없으면 환경변수 RSCRIPT로 지정한다.

declare(strict_types=1);

const ALLOWED_EXT = ['bin', 'rda', 'rdata'];

$ROOT = dirname(__DIR__);
$SAMPLES = $ROOT . '/outputs/samples';
$RSCRIPT = getenv('RSCRIPT') ?: 'Rscript';

function h($s): string
{
    return htmlspecialchars((string) $s, ENT_QUOTES, 'UTF-8');
}

// run.R 호출. 사용자 입력은 JSON 파일로만 넘기고, 셸 인자는 서버가 만든 경로뿐이다.
function run_r(string $action, array $args, string $work_dir): array
{
    global $ROOT, $RSCRIPT;

    $in = $work_dir . '/' . $action . '.in.json';
    $out = $work_dir . '/' . $action . '.json';
    file_put_contents($in, json_encode(['action' => $action, 'args' => $args], JSON_UNESCAPED_UNICODE));

    $cmd = escapeshellarg($RSCRIPT) . ' ' . escapeshellarg($ROOT . '/R/run.R') . ' '
        . escapeshellarg($in) . ' ' . escapeshellarg($out) . ' 2>&1';
    exec($cmd, $console, $status);

    if (!is_file($out)) {
        // R이 출력 파일조차 못 쓴 경우(예: Rscript 없음). 콘솔 마지막 줄을 보여 준다.
        return ['ok' => false, 'error' => 'R 실행 실패(종료 코드 ' . $status . '): ' . implode(' / ', array_slice($console, -3))];
    }

    return json_decode((string) file_get_contents($out), true) ?? ['ok' => false, 'error' => 'R 출력 JSON 읽기 실패.'];
}

function sample_dir(string $id): ?string
{
    global $SAMPLES;
    return preg_match('/^[0-9]{8}-[0-9]{6}-[0-9a-f]{6}$/', $id) ? $SAMPLES . '/' . $id : null;
}

$error = null;

// ---- 업로드 (POST) → 저장 → inspect → 결과 페이지로 이동 (POST-Redirect-GET)
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
        mkdir($dir . '/raw', 0775, true);

        // 저장 이름은 서버가 정한다. 원래 파일명은 기록만 한다.
        $path = $dir . '/raw/input.' . $ext;
        move_uploaded_file($f['tmp_name'], $path);
        file_put_contents($dir . '/meta.json', json_encode(
            ['original_name' => $f['name'], 'uploaded_at' => date('c'), 'size' => $f['size']],
            JSON_UNESCAPED_UNICODE
        ));

        run_r('inspect', ['path' => $path], $dir);
        header('Location: ?sample=' . $id);
        exit;
    }
}

// ---- 결과 페이지 (GET ?sample=...)
$sample = null;
if (isset($_GET['sample'])) {
    $dir = sample_dir((string) $_GET['sample']);
    if ($dir === null || !is_file($dir . '/inspect.json')) {
        $error = '샘플을 찾을 수 없음.';
    } else {
        $sample = [
            'id' => $_GET['sample'],
            'meta' => json_decode((string) file_get_contents($dir . '/meta.json'), true),
            'inspect' => json_decode((string) file_get_contents($dir . '/inspect.json'), true),
        ];
    }
}
?>
<!doctype html>
<html lang="ko">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Luminous</title>
<style>
  :root { --fg: #1d2330; --muted: #667085; --line: #e4e7ec; --accent: #2563eb; --bg: #f8fafc; --err: #b42318; }
  * { box-sizing: border-box; }
  body { margin: 0; font: 15px/1.5 -apple-system, "Apple SD Gothic Neo", "Segoe UI", sans-serif; color: var(--fg); background: var(--bg); }
  main { max-width: 960px; margin: 0 auto; padding: 20px 16px 40px; }
  h1 { font-size: 22px; margin: 0 0 4px; }
  h2 { font-size: 17px; margin: 28px 0 10px; }
  .sub { color: var(--muted); margin: 0 0 20px; }
  .card { background: #fff; border: 1px solid var(--line); border-radius: 10px; padding: 16px; }
  .err { color: var(--err); border-color: #fecdca; background: #fef3f2; margin-bottom: 16px; }
  .facts { display: grid; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); gap: 10px; }
  .fact b { display: block; font-size: 20px; }
  .fact span { color: var(--muted); font-size: 13px; }
  table { width: 100%; border-collapse: collapse; background: #fff; }
  th, td { text-align: left; padding: 8px 10px; border-bottom: 1px solid var(--line); vertical-align: top; }
  th { font-size: 13px; color: var(--muted); font-weight: 600; }
  .tag { display: inline-block; padding: 1px 8px; border-radius: 999px; background: #eff4ff; color: var(--accent); font-size: 13px; }
  .grains { color: var(--muted); font-size: 13px; }
  button { background: var(--accent); color: #fff; border: 0; border-radius: 8px; padding: 10px 16px; font-size: 15px; }
  a { color: var(--accent); }
</style>
</head>
<body>
<main>
  <h1>Luminous</h1>
  <p class="sub">루미네선스 측정 파일(BIN/RDA)을 올리면 디스크와 알갱이 구성을 보여 줌.</p>

  <?php if ($error): ?>
    <div class="card err"><?= h($error) ?></div>
  <?php endif; ?>

  <?php if (!$sample): ?>
    <form class="card" method="post" enctype="multipart/form-data">
      <p><input type="file" name="bin" accept=".bin,.BIN,.rda,.rdata,.RData" required></p>
      <button type="submit">업로드하고 확인</button>
    </form>
  <?php else:
      $r = $sample['inspect'];
      if (!$r['ok']): ?>
    <div class="card err">분석 실패: <?= h($r['error']) ?></div>
  <?php else:
        $x = $r['result'];
        $by_disc = [];
        foreach ($x['grains'] as $g) { $by_disc[$g['position']][] = $g['grain']; }
        $n_records = count($x['records']);
  ?>
    <div class="card facts">
      <div class="fact"><b><?= h($sample['meta']['original_name']) ?></b><span>파일</span></div>
      <div class="fact"><b><span class="tag"><?= $x['single_grain'] ? 'single-grain' : 'single-aliquot' ?></span></b><span>측정 방식</span></div>
      <div class="fact"><b><?= h($x['n_positions']) ?></b><span>디스크(POSITION)</span></div>
      <div class="fact"><b><?= $x['single_grain'] ? h(count($x['grains'])) : '—' ?></b><span>알갱이(GRAIN)</span></div>
      <div class="fact"><b><?= h($n_records) ?></b><span>레코드</span></div>
      <div class="fact"><b><?= h(implode(', ', $x['record_types'])) ?></b><span>레코드 종류</span></div>
    </div>

    <h2>디스크 목록</h2>
    <table>
      <tr><th>디스크</th><th>알갱이 수</th><th>알갱이 번호</th></tr>
      <?php foreach ($by_disc as $pos => $grains): ?>
        <tr>
          <td><?= h($pos) ?></td>
          <td><?= $x['single_grain'] ? h(count($grains)) : '—' ?></td>
          <td class="grains"><?= $x['single_grain'] ? h(implode(', ', $grains)) : '디스크 단위 측정' ?></td>
        </tr>
      <?php endforeach; ?>
    </table>

    <p class="sub" style="margin-top:16px">
      분석 패키지: Luminescence <?= h($r['meta']['luminescence_version']) ?> · R <?= h($r['meta']['r_version']) ?> ·
      샘플 <?= h($sample['id']) ?> · <a href="?">다른 파일 올리기</a>
    </p>
  <?php endif; endif; ?>
</main>
</body>
</html>
