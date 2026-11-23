<?php
declare(strict_types=1);
// Runs the offline PHP suites in one process under Xdebug and writes SonarQube generic coverage XML.
// Usage: XDEBUG_MODE=coverage php Server/tests/coverage.php build/coverage/php-coverage.xml
if (!function_exists('xdebug_start_code_coverage')) {
    fwrite(STDERR, "Xdebug coverage mode is required.\n");
    exit(2);
}
$output = $argv[1] ?? 'build/coverage/php-coverage.xml';
$root = realpath(__DIR__ . '/../..');
register_shutdown_function(function () use ($output, $root): void {
    $data = xdebug_get_code_coverage();
    xdebug_stop_code_coverage();
    $xml = new DOMDocument('1.0', 'UTF-8');
    $xml->formatOutput = true;
    $coverage = $xml->appendChild($xml->createElement('coverage'));
    $coverage->setAttribute('version', '1');
    ksort($data);
    foreach ($data as $file => $lines) {
        $real = realpath($file);
        if ($real === false || !str_starts_with($real, $root . '/Server/')) continue;
        if (str_starts_with($real, $root . '/Server/tests/')) continue;
        $node = $coverage->appendChild($xml->createElement('file'));
        $node->setAttribute('path', substr($real, strlen($root) + 1));
        ksort($lines);
        foreach ($lines as $number => $hits) {
            // Xdebug: 1 executed, -1 executable but not executed, -2 dead code (not executable).
            if ($hits === -2) continue;
            $line = $node->appendChild($xml->createElement('lineToCover'));
            $line->setAttribute('lineNumber', (string)$number);
            $line->setAttribute('covered', $hits > 0 ? 'true' : 'false');
        }
    }
    @mkdir(dirname($output), 0777, true);
    $xml->save($output);
});
xdebug_start_code_coverage(XDEBUG_CC_UNUSED | XDEBUG_CC_DEAD_CODE);
ob_start();
require __DIR__ . '/run.php';
require __DIR__ . '/apns_response_test.php';
fwrite(STDOUT, ob_get_clean());
