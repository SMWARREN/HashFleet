<?php
declare(strict_types=1);
final class FleetAPIException extends RuntimeException {}
umask(0077);
ini_set('display_errors', '0');
header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');
header('X-Content-Type-Options: nosniff');
header('Referrer-Policy: no-referrer');
header('X-Frame-Options: DENY');
header("Content-Security-Policy: default-src 'none'; frame-ancestors 'none'");

try {
    // Production layout: ~/hashfleet.app/api/v1.php and ~/hashfleet-private/, never inside public/.
    $private = getenv('HASHFLEET_PRIVATE') ?: dirname(__DIR__, 2) . '/hashfleet-private';
    if (!is_file($private . '/config.php')) {
        throw new FleetAPIException('Unconfigured service');
    }
    // Keep require's returned config array; require_once returns true on repeat inclusion.
    $config = require $private . '/config.php';
    require_once $private . '/Service.php';
    $remote = $_SERVER['REMOTE_ADDR'] ?? '';
    $https = !empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off';
    $localTesting = !empty($config['allow_local_http']) && in_array($remote, ['127.0.0.1', '::1'], true);
    if (!$https && !$localTesting) {
        throw new FleetHttpError(400, 'HTTPS is required.');
    }
    $action = $_GET['action'] ?? '';
    if (!is_string($action) || !in_array($action, ['health', 'register', 'preferences', 'status'], true)
        || array_diff(array_keys($_GET), ['action'])) {
        throw new FleetHttpError(404, 'Not found.');
    }
    $method = $_SERVER['REQUEST_METHOD'] ?? 'GET';
    if (!in_array($method, ['GET', 'POST', 'PUT', 'DELETE'], true)) {
        throw new FleetHttpError(405, 'Method not allowed.');
    }
    $headers = [];
    foreach (function_exists('getallheaders') ? getallheaders() : [] as $key => $value) {
        $headers[strtolower($key)] = $value;
    }
    $headers['authorization'] ??= $_SERVER['HTTP_AUTHORIZATION'] ?? $_SERVER['REDIRECT_HTTP_AUTHORIZATION'] ?? '';
    $headers['x-hashfleet-installation'] ??= $_SERVER['HTTP_X_HASHFLEET_INSTALLATION'] ?? '';
    $body = null;
    if ($method === 'POST' || $method === 'PUT') {
        if (strtolower(trim(explode(';', $_SERVER['CONTENT_TYPE'] ?? '')[0])) !== 'application/json') {
            throw new FleetHttpError(415, 'Use application/json.');
        }
        if ((int)($_SERVER['CONTENT_LENGTH'] ?? 0) > 131072) {
            throw new FleetHttpError(413, 'Request is too large.');
        }
        $stream = fopen('php://input', 'rb');
        if (!$stream) {
            throw new FleetAPIException('Input unavailable');
        }
        $raw = stream_get_contents($stream, 131073);
        fclose($stream);
        if ($raw === false) {
            throw new FleetAPIException('Input unavailable');
        }
        $body = FleetService::decodeBody($raw);
    }
    $service = new FleetService($config);
    echo json_encode($service->handle($method, $action, $headers, $body, $remote), JSON_THROW_ON_ERROR | JSON_UNESCAPED_UNICODE);
} catch (Throwable $error) {
    $known = $error instanceof FleetHttpError;
    $status = $known ? $error->status : 503;
    http_response_code($status);
    if ($status === 429) {
        header('Retry-After: 60');
    }
    // Never expose file paths, keys, database errors or raw exception messages.
    echo json_encode(['ok' => false, 'error' => $known ? $error->getMessage() : 'Notification service is unavailable.']);
}
