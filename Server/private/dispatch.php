#!/usr/bin/env php
<?php
declare(strict_types=1);
final class FleetDispatcherException extends RuntimeException {}
if (PHP_SAPI !== 'cli') { http_response_code(404); exit; }
umask(0077);
$private = getenv('HASHFLEET_PRIVATE') ?: __DIR__;
$lock = null;
try {
    // Keep require's returned config array; require_once returns true on repeat inclusion.
    $config = require $private . '/config.php';
    require_once $private . '/Service.php';
    $lock = fopen($private . '/dispatcher.lock', 'c');
    if (!$lock) {
        throw new FleetDispatcherException('Lock unavailable');
    }
    if (!flock($lock, LOCK_EX | LOCK_NB)) { fwrite(STDOUT, "Another dispatcher owns this run.\n"); exit(0); }
    $service = new FleetService($config);
    if (in_array('--check', $argv, true)) {
        fwrite(STDOUT, json_encode(['ok' => true, 'provider_ready' => $service->providerReady()]) . "\n");
    } else {
        $count = $service->dispatchDue();
        fwrite(STDOUT, "APNs requests attempted: {$count}. Acceptance is not device delivery.\n");
    }
} catch (Throwable) { fwrite(STDERR, "HashFleet dispatcher failed safely.\n"); exit(1); }
finally { if (is_resource($lock)) { flock($lock, LOCK_UN); fclose($lock); } }
