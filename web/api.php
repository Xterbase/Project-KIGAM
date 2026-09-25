<?php
// web/api.php — 대시보드(assets/app.js)의 fetch를 받아 R(run.R)을 실행하고 결과 JSON을 그대로 돌려준다.
//
// 요청: POST {"id": "<샘플 id>", "action": "<동작>", "args": {...}}
// 응답: run.R의 출력 그대로 {"ok", "action", "result" | "error", "meta"}
//
// 측정 파일 경로는 서버가 붙인다. 브라우저가 보낸 args는 동작별 허용 키만 R로 넘긴다
// (path, progress_file처럼 서버 파일을 가리키는 인자를 브라우저가 정하지 못하게).

declare(strict_types=1);

require __DIR__ . '/../php/bridge.php';

// 동작 => [허용 args 키, 측정 파일 필요 여부, 결과 기록 파일(null이면 표시용이라 남기지 않음)]
const ACTIONS = [
    'curve' => [['position', 'record_index', 'grain', 'mode'], true, null],
    'dose_response' => [['position', 'signal_integral', 'background_integral', 'grain', 'mode', 'seed'], true, null],
    'sar' => [['positions', 'signal_integral', 'background_integral', 'mode', 'seed'], true, 'sar.json'],
    'age_model' => [['de', 'de_error', 'sigmab', 'model', 'max_k'], false, 'age_model.json'],
];

header('Content-Type: application/json; charset=utf-8');

function fail(int $code, string $msg): void
{
    http_response_code($code);
    echo json_encode(['ok' => false, 'error' => $msg], JSON_UNESCAPED_UNICODE);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    fail(405, 'POST 요청만 받음.');
}

$req = json_decode((string) file_get_contents('php://input'), true);
$action = is_array($req) ? ($req['action'] ?? null) : null;
if (!is_string($action) || !isset(ACTIONS[$action]) || !is_array($req['args'] ?? null)) {
    fail(400, '잘못된 요청 형식.');
}

$dir = sample_dir((string) ($req['id'] ?? ''));
if ($dir === null || !is_dir($dir)) {
    fail(404, '샘플을 찾을 수 없음.');
}

[$keys, $needs_file, $keep_as] = ACTIONS[$action];
$args = array_intersect_key($req['args'], array_flip($keys));

if ($needs_file) {
    $args['path'] = sample_input($dir);
    if ($args['path'] === null) {
        fail(404, '측정 파일이 없음.');
    }
}

$result = run_r($action, $args, $dir, $keep_as);
echo json_encode($result, JSON_UNESCAPED_UNICODE);
