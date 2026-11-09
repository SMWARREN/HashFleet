<?php
declare(strict_types=1);
require_once __DIR__ . '/../private/APNs.php';

// No cURL request, provider configuration or private signing key is loaded.
$parse = new ReflectionMethod(FleetAPNs::class, 'retryAfterHeader');
$now = 1794206400;
$cases = [
    ["Content-Type: application/json\r\n", 17, 17],
    ["Retry-After: 0\r\n", 17, 0],
    ["retry-after: 120\r\n", 17, 120],
    ["RETRY-AFTER: 7200\r\n", 17, 3600],
    ["Retry-After: 999999999999999999999999999\r\n", 17, 3600],
    ["Retry-After: " . gmdate('D, d M Y H:i:s \G\M\T', $now + 90) . "\r\n", 17, 90],
    ["Retry-After: " . gmdate('D, d M Y H:i:s \G\M\T', $now - 90) . "\r\n", 17, 0],
    ["Retry-After: not-a-date\r\n", 17, 0],
    ["Retry-After:\r\n", 17, 0],
    ["X-Retry-After: 120\r\n", 17, 17],
];
foreach ($cases as $index => [$header, $current, $expected]) {
    if ($parse->invoke(null, $header, $now, $current) !== $expected) {
        throw new LogicException('Retry-After case failed: ' . $index);
    }
}
fwrite(STDOUT, 'PASS: ' . count($cases) . " offline Retry-After cases\n");

$signature = hex2bin('3006020101020102');
$expected = str_repeat("\0", 31) . "\x01" . str_repeat("\0", 31) . "\x02";
if (FleetAPNs::derToJose($signature) !== $expected) {
    throw new LogicException('Valid DER signature conversion changed');
}
$invalid = ['', "\x30", hex2bin('3106020101020102'),
    hex2bin('3006020180020102'), $signature . "\0"];
foreach ($invalid as $index => $der) {
    $caught = null;
    try {
        FleetAPNs::derToJose($der);
    } catch (RuntimeException $error) {
        $caught = $error;
    }
    if (!$caught instanceof FleetAPNsException || $caught->getMessage() !== 'Invalid signature') {
        throw new LogicException('DER rejection or RuntimeException compatibility changed: ' . $index);
    }
}
fwrite(STDOUT, "PASS: valid DER conversion and 5 RuntimeException-compatible rejections\n");
