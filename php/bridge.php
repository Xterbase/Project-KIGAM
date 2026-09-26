<?php
// php/bridge.php — web/의 페이지들이 함께 쓰는 R 호출·샘플 경로 함수.
//
// DocumentRoot(web/) 밖에 두어 URL로 직접 실행될 수 없게 한다.
// URL로 열리는 파일은 web/의 페이지뿐이라는 규칙을 단순하게 유지하기 위해서다.
//
// Rscript 경로가 PATH에 없으면 환경변수 RSCRIPT로 지정한다.

declare(strict_types=1);

define('ROOT', dirname(__DIR__));
define('SAMPLES', ROOT . '/outputs/samples');
define('RSCRIPT', getenv('RSCRIPT') ?: 'Rscript');

const ALLOWED_EXT = ['bin', 'rda', 'rdata'];

// 샘플 id와 업로드 시각은 한국 시간. php.ini가 UTC로 정해 둔 서버도 있어 여기서 고정한다.
date_default_timezone_set('Asia/Seoul');

function h($s): string
{
    return htmlspecialchars((string) $s, ENT_QUOTES, 'UTF-8');
}

// 샘플 id → 폴더 경로. id 형식이 틀리면 null(경로 조작 차단). 폴더가 있는지는 보지 않는다.
function sample_dir(string $id): ?string
{
    return preg_match('/^[0-9]{8}-[0-9]{6}-[0-9a-f]{6}$/', $id) ? SAMPLES . '/' . $id : null;
}

// 업로드된 측정 파일 경로(raw/input.{ext}). 없으면 null.
function sample_input(string $dir): ?string
{
    return glob($dir . '/raw/input.*')[0] ?? null;
}

function read_json(string $path): ?array
{
    return is_file($path) ? json_decode((string) file_get_contents($path), true) : null;
}

// 샘플 목록(최신순). 폴더 이름이 시각으로 시작하므로 이름 역순 = 최신순. index.php와 dashboard.php가 함께 쓴다.
function list_samples(): array
{
    $samples = [];
    foreach (array_reverse(glob(SAMPLES . '/*', GLOB_ONLYDIR) ?: []) as $d) {
        $id = basename($d);
        $meta = read_json($d . '/meta.json');
        if (sample_dir($id) !== null && $meta !== null) {
            $samples[] = ['id' => $id] + $meta;
        }
    }
    return $samples;
}

// 목록 표의 측정 방식 칸
function sample_mode(array $s): string
{
    if (($s['ok'] ?? true) === false) {
        return '<span class="no">읽기 실패</span>';
    }
    return isset($s['single_grain']) ? ($s['single_grain'] ? 'single-grain' : 'single-aliquot') : '—';
}

// run.R 호출. 사용자 입력은 JSON 파일로만 넘기고, 셸 인자는 서버가 만든 경로뿐이다.
// 요청마다 파일 이름이 달라서 동시에 들어온 요청이 서로의 입출력을 덮어쓰지 않는다.
// $keep_as를 주면 출력을 그 이름으로 샘플 폴더에 남긴다(결과 기록). 아니면 지운다(표시용).
function run_r(string $action, array $args, string $work_dir, ?string $keep_as = null): array
{
    $tag = $work_dir . '/' . $action . '-' . bin2hex(random_bytes(4));
    $in = $tag . '.in.json';
    $out = $tag . '.json';
    file_put_contents($in, json_encode(['action' => $action, 'args' => $args], JSON_UNESCAPED_UNICODE));

    $cmd = escapeshellarg(RSCRIPT) . ' ' . escapeshellarg(ROOT . '/R/run.R') . ' '
        . escapeshellarg($in) . ' ' . escapeshellarg($out) . ' 2>&1';
    exec($cmd, $console, $status);
    unlink($in);

    if (!is_file($out)) {
        // R이 출력 파일조차 못 쓴 경우(예: Rscript 없음). 콘솔 마지막 줄을 보여 준다.
        return ['ok' => false, 'error' => 'R 실행 실패(종료 코드 ' . $status . '): ' . implode(' / ', array_slice($console, -3))];
    }

    $result = read_json($out) ?? ['ok' => false, 'error' => 'R 출력 JSON 읽기 실패.'];
    $keep_as === null ? unlink($out) : rename($out, $work_dir . '/' . $keep_as);

    return $result;
}
