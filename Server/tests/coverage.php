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
        // The installer runs from a temporary bundle copy. Report it under its repository path.
        $copy = $GLOBALS['installerCopy'] ?? null;
        if ($real !== false && $copy !== null && $real === realpath($copy)) $real = $root . '/Server/tools/install.php';
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

// Run the real CLI installer in-process against a synthetic verified bundle and an isolated home.
function runInstallerForCoverage(string $root): string {
    $temp = sys_get_temp_dir() . '/hashfleet-install-cov-' . bin2hex(random_bytes(4));
    $bundle = $temp . '/bundle';
    $fakeHome = $temp . '/home';
    mkdir($bundle, 0700, true);
    mkdir($fakeHome . '/hashfleet.app', 0700, true);
    $files = ['web/index.html', 'web/app.js', 'web/style.css', 'web/.htaccess', 'web/api/v1.php', 'web/companion/index.html',
        'private/Service.php', 'private/APNs.php', 'private/dispatch.php', 'private/config.example.php',
        'web/assets/index-abcdefgh12.js', 'web/assets/index-abcdefgh12.css', 'web/images/logo.png', 'web/robots.txt'];
    $manifest = [];
    foreach ($files as $relative) {
        $path = $bundle . '/' . $relative;
        if (!is_dir(dirname($path))) mkdir(dirname($path), 0700, true);
        file_put_contents($path, 'fixture:' . $relative);
        $manifest[$relative] = hash('sha256', 'fixture:' . $relative);
    }
    // A pre-existing file exercises the backup branch.
    file_put_contents($fakeHome . '/hashfleet.app/index.html', 'old');
    file_put_contents($bundle . '/manifest.json', json_encode($manifest));
    $GLOBALS['installerCopy'] = $bundle . '/install.php';
    copy($root . '/Server/tools/install.php', $GLOBALS['installerCopy']);
    return $fakeHome;
}
$installerHome = runInstallerForCoverage($root);
$argv = [$argv[0], $installerHome];
$installerCopy = $GLOBALS['installerCopy'];
require $installerCopy;
fwrite(STDOUT, ob_get_clean());
