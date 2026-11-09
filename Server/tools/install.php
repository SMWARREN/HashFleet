<?php
/** CLI-only, allowlisted deployment. Never deletes unrelated files or replaces private configuration/data. */
declare(strict_types=1);
if (PHP_SAPI !== 'cli') { http_response_code(404); exit; }
umask(0077);
ini_set('display_errors', '0');
$fixed = ['web/index.html', 'web/app.js', 'web/style.css', 'web/.htaccess', 'web/api/v1.php', 'web/companion/index.html',
    'private/Service.php', 'private/APNs.php', 'private/dispatch.php', 'private/config.example.php'];
function directory(string $path, int $mode): void {
    if (is_link($path) || (file_exists($path) && !is_dir($path))) throw new RuntimeException('Unsafe destination directory.');
    if (!is_dir($path)) {
        if (!mkdir($path, $mode, false)) throw new RuntimeException('Could not create scoped directory.');
        chmod($path, $mode);
    }
}
function parentDirectories(string $base, string $target, int $mode): void {
    $relative = substr(dirname($target), strlen($base));
    $cursor = rtrim($base, '/');
    foreach (array_filter(explode('/', trim($relative, '/')), 'strlen') as $part) {
        if ($part === '.' || $part === '..') throw new RuntimeException('Unsafe destination path.');
        $cursor .= '/' . $part;
        directory($cursor, $mode);
    }
}
function atomicCopy(string $source, string $target, int $mode): void {
    if (is_link($target) || (file_exists($target) && !is_file($target))) throw new RuntimeException('Unsafe destination file.');
    $temporary = dirname($target) . '/.hashfleet-' . bin2hex(random_bytes(8));
    try {
        if (!copy($source, $temporary) || !chmod($temporary, $mode) || !rename($temporary, $target)) throw new RuntimeException('Could not promote scoped file.');
    } finally { if (is_file($temporary)) unlink($temporary); }
}
function allowedAsset(string $path): bool {
    if (preg_match('~^web/assets/[A-Za-z0-9_-]+-[A-Za-z0-9_-]{8,}\.(?:js|css)$~D', $path)) return true;
    if (preg_match('~^web/(?:assets|images)/[A-Za-z0-9._/-]+\.(?:png|jpe?g|gif|svg|webp|avif|ico|woff2?)$~D', $path)) {
        foreach (explode('/', $path) as $part) if ($part === '' || $part === '.' || $part === '..') return false;
        return true;
    }
    return in_array($path, ['web/_headers', 'web/apple-touch-icon.png', 'web/favicon.png', 'web/robots.txt',
        'web/sitemap.xml', 'web/social-card.png'], true);
}
$backup = null; $promoted = []; $targets = []; $createdConfiguration = false; $configuration = null;
try {
    $home = realpath($argv[1] ?? (getenv('HOME') ?: ''));
    if (!$home || $home === '/' || is_link($home . '/hashfleet.app') || !is_dir($home . '/hashfleet.app')) throw new RuntimeException('The existing HashFleet webroot must be verified first.');
    $bundleRoot = realpath(__DIR__);
    $manifestPath = __DIR__ . '/manifest.json';
    if (!$bundleRoot || is_link($manifestPath) || !is_file($manifestPath)) throw new RuntimeException('Unsafe bundle directory.');
    $manifest = json_decode(file_get_contents($manifestPath), true, 32, JSON_THROW_ON_ERROR);
    if (!is_array($manifest) || array_is_list($manifest)) throw new RuntimeException('Invalid bundle manifest.');
    $keys = array_keys($manifest); sort($keys); $expected = $fixed; sort($expected);
    foreach ($keys as $key) if (!in_array($key, $fixed, true) && !allowedAsset($key)) throw new RuntimeException('Bundle file allowlist mismatch.');
    foreach ($expected as $key) if (!array_key_exists($key, $manifest)) throw new RuntimeException('Required bundle file is missing.');
    $hasJs = $hasCss = false;
    foreach ($keys as $relative) {
        $source = __DIR__ . '/' . $relative;
        $cursor = __DIR__;
        foreach (explode('/', $relative) as $part) {
            $cursor .= '/' . $part;
            if (is_link($cursor)) throw new RuntimeException('Symlink in bundle source path.');
        }
        if (!is_string($manifest[$relative]) || !preg_match('/^[a-f0-9]{64}$/D', $manifest[$relative])) throw new RuntimeException('Invalid bundle digest.');
        $prefix = $bundleRoot . '/';
        $realSource = realpath($source);
        if (is_link($source) || !$realSource || !str_starts_with($realSource, $prefix) || !is_file($realSource)
            || !hash_equals($manifest[$relative], hash_file('sha256', $realSource))) throw new RuntimeException('Bundle integrity check failed.');
        if (preg_match('~^web/assets/[A-Za-z0-9_-]+-[A-Za-z0-9_-]{8,}\.js$~D', $relative)) $hasJs = true;
        if (preg_match('~^web/assets/[A-Za-z0-9_-]+-[A-Za-z0-9_-]{8,}\.css$~D', $relative)) $hasCss = true;
    }
    if (!$hasJs || !$hasCss) throw new RuntimeException('Hashed website script and stylesheet are required.');
    $web = $home . '/hashfleet.app'; $private = $home . '/hashfleet-private';
    directory($private, 0700); chmod($private, 0700); directory($private . '/backups', 0700);
    $backup = $private . '/backups/' . gmdate('Ymd-His') . '-' . bin2hex(random_bytes(4));
    directory($backup, 0700);
    foreach (['web', 'private'] as $part) directory($backup . '/' . $part, 0700);
    directory($web . '/api', 0755); directory($web . '/companion', 0755);
    foreach ($keys as $relative) {
        $isWeb = str_starts_with($relative, 'web/');
        $base = $isWeb ? $web : $private;
        $subpath = $isWeb ? substr($relative, 4) : substr($relative, 8);
        $target = $base . '/' . $subpath;
        parentDirectories($base, $target, $isWeb ? 0755 : 0700);
        parentDirectories($backup . '/' . ($isWeb ? 'web' : 'private'), $backup . '/' . $relative, 0700);
        if (is_link($target) || (file_exists($target) && !is_file($target))) throw new RuntimeException('Unsafe destination file.');
        $exists = is_file($target);
        if ($exists && !copy($target, $backup . '/' . $relative)) throw new RuntimeException('Backup failed.');
        $targets[$relative] = ['path' => $target, 'existed' => $exists, 'mode' => $exists ? (fileperms($target) & 0777) : null];
    }
    $configuration = $private . '/config.php';
    if (is_link($configuration) || (file_exists($configuration) && !is_file($configuration))) throw new RuntimeException('Unsafe private configuration.');
    $createdConfiguration = !is_file($configuration);
    if ($createdConfiguration) {
        $config = ['database' => $private . '/hashfleet.sqlite', 'privacy_salt' => bin2hex(random_bytes(32)),
            'allow_local_http' => false, 'apns' => ['key_file' => null, 'key_id' => null, 'team_id' => null,
                'topic' => 'app.hashfleet', 'jwt_cache' => $private . '/apns-jwt.json']];
        $handle = fopen($configuration, 'x');
        if (!$handle) throw new RuntimeException('Private configuration could not be created.');
        $text = "<?php\ndeclare(strict_types=1);\nreturn " . var_export($config, true) . ";\n";
        try { if (fwrite($handle, $text) !== strlen($text)) throw new RuntimeException('Incomplete private configuration.'); }
        finally { fclose($handle); }
        chmod($configuration, 0600);
    } elseif ((fileperms($configuration) & 0077) !== 0) throw new RuntimeException('Existing private configuration is not private.');
    $order = array_values(array_filter($keys, fn($path) => $path !== 'web/.htaccess'));
    $order[] = 'web/.htaccess';
    foreach ($order as $relative) {
        $promoted[] = $relative;
        atomicCopy(__DIR__ . '/' . $relative, $targets[$relative]['path'], str_starts_with($relative, 'web/') ? 0644 : 0600);
    }
    file_put_contents($backup . '/deployment.json', json_encode(['at' => gmdate('c'), 'files' => $targets, 'manifest' => $manifest], JSON_PRETTY_PRINT | JSON_THROW_ON_ERROR));
    fwrite(STDOUT, json_encode(['ok' => true, 'files' => count($keys), 'backup' => $backup,
        'private_config_created' => $createdConfiguration, 'provider_activation' => 'not_performed'], JSON_THROW_ON_ERROR) . "\n");
} catch (Throwable) {
    foreach (array_reverse($promoted) as $relative) {
        if (!isset($targets[$relative])) continue;
        $target = $targets[$relative];
        if ($target['existed']) atomicCopy($backup . '/' . $relative, $target['path'], $target['mode']);
        elseif (is_file($target['path']) && !is_link($target['path'])) unlink($target['path']);
    }
    if ($createdConfiguration && $configuration && is_file($configuration) && !is_link($configuration)) unlink($configuration);
    fwrite(STDERR, "Scoped HashFleet deployment failed. Promoted files were rolled back; inspect private backups.\n");
    exit(1);
}
