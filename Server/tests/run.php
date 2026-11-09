<?php
declare(strict_types=1);
require_once __DIR__ . '/../private/Service.php';

$checks = 0;
function check(bool $condition, string $name): void {
    global $checks;
    if (!$condition) throw new RuntimeException('FAIL: ' . $name);
    $checks++;
}
function rejects(int $status, Closure $operation, string $name): void {
    $caught = null;
    try { $operation(); } catch (FleetHttpError $error) { $caught = $error; }
    // Deliberately outside the catch: an unexpectedly accepted request can never pass.
    check($caught?->status === $status, $name);
}
final class Fixture {
    public int $now = 1792886400;
    public PDO $db;
    public FleetService $service;
    public array $sent = [];
    public int $response = 200;
    public int $retryAfter = 0;
    public ?Closure $duringSend = null;
    public string $id = '11111111-1111-4111-8111-111111111111';
    public string $miner = '22222222-2222-4222-8222-222222222222';
    public string $other = '33333333-3333-4333-8333-333333333333';
    public string $secret;
    public array $config = ['database' => ':memory:', 'privacy_salt' => 'offline-only-fixture'];
    public function __construct(bool $withSender = true, ?PDO $db = null, bool $initializeService = true) {
        $this->secret = FleetAPNs::base64url(random_bytes(32));
        $this->db = $db ?? new PDO('sqlite::memory:');
        $sender = $withSender ? function ($job, $payload): array {
            $this->sent[] = $payload;
            if ($this->duringSend) ($this->duringSend)($job);
            return ['status' => $this->response, 'retry_after' => $this->retryAfter];
        } : null;
        if ($initializeService) $this->service = new FleetService($this->config, $this->db, fn() => $this->now, $sender);
    }
    public function headers(?string $secret = null, ?string $id = null): array {
        return ['authorization' => 'Bearer ' . ($secret ?? $this->secret), 'x-hashfleet-installation' => $id ?? $this->id];
    }
    public function registration(?string $token = null, ?array $miners = null): array {
        return ['mode' => 'device_check_v1', 'device_token' => $token ?? str_repeat('ab', 32),
            'environment' => 'sandbox', 'miners' => $miners ?? [['id' => $this->miner]]];
    }
    public function register(?string $token = null, ?array $miners = null): array {
        return $this->call('POST', 'register', $this->registration($token, $miners));
    }
    public function call(string $method, string $action, ?array $body = null, ?array $headers = null): array {
        return $this->service->handle($method, $action, $headers ?? $this->headers(), $body, '192.0.2.10');
    }
    public function schedule(bool $enabled = true, int $interval = 60, ?array $ids = null): array {
        $ids ??= [$this->miner];
        return ['enabled' => $enabled, 'miners' => array_map(static fn($id) => [
            'id' => $id, 'enabled' => true, 'interval_minutes' => $interval], $ids)];
    }
    public function enable(int $interval = 60): void { $this->call('PUT', 'preferences', $this->schedule(true, $interval)); }
    public function scalar(string $sql): mixed { return $this->db->query($sql)->fetchColumn(); }
    public function nextDue(): int { return (int)$this->scalar('SELECT next_due FROM miners ORDER BY id LIMIT 1'); }
    public function due(): void { $this->now = $this->nextDue(); }
}

check(FleetService::decodeBody('{}') === [], 'empty JSON object is valid');
foreach (['[]', 'null', 'true', '"text"', '{broken', '{"value":NaN}'] as $raw) {
    rejects(400, fn() => FleetService::decodeBody($raw), 'invalid JSON root rejected');
}
rejects(413, fn() => FleetService::decodeBody(str_repeat('x', 131073)), 'oversized request rejected');

$f = new Fixture();
check($f->service->handle('GET', 'health', []) === ['ok' => true, 'service' => 'hashfleet-notifications',
    'mode' => 'device_check_v1', 'provider_ready' => false], 'health exposes only minimal mode/readiness metadata');
$r = $f->register();
check($r['ok'] === true && $r['mode'] === 'device_check_v1' && $r['settings']['enabled'] === false,
    'new installation starts globally disabled');
check($r['settings']['miners'] === [['id' => $f->miner, 'enabled' => true, 'interval_minutes' => 60]],
    'new miner defaults enabled at hourly cadence without name');
check(strlen($f->scalar('SELECT credential_hash FROM installations')) === 64, 'only credential digest stored');
check($f->scalar('SELECT credential_hash FROM installations') !== $f->secret, 'admin secret not stored plaintext');
$status = $f->call('GET', 'status');
check(isset($status['token_valid'], $status['schedules']) && !isset($status['token'], $status['device_token']),
    'status contains token validity and schedule metadata but no APNs token');
check(!str_contains(json_encode($status), $f->secret) && !str_contains(json_encode($status), 'Workshop'),
    'status exposes neither credentials nor miner names');
$wrong = $f->headers(FleetAPNs::base64url(random_bytes(32)));
rejects(401, fn() => $f->call('GET', 'status', null, $wrong), 'wrong credential cannot read');
$padded = $f->headers($f->secret . '=');
rejects(401, fn() => $f->call('GET', 'status', null, $padded), 'noncanonical padded bearer is rejected');
$shortBearer = $f->headers(substr($f->secret, 0, -1));
rejects(401, fn() => $f->call('GET', 'status', null, $shortBearer), 'short bearer is rejected');
rejects(401, fn() => $f->call('POST', 'register', $f->registration(), $wrong), 'known installation cannot be hijacked');
check(!$f->db->inTransaction(), 'failed ownership transaction rolled back');
rejects(401, fn() => $f->call('DELETE', 'register', null, $wrong), 'wrong credential cannot delete');
$otherHeaders = $f->headers(null, $f->other);
rejects(409, fn() => $f->call('POST', 'register', $f->registration(), $otherHeaders), 'duplicate APNs token cannot transfer ownership');
check($f->scalar('SELECT COUNT(*) FROM installations') === 1, 'conflicting registration made no installation');
foreach ([
    ['extra' => 'wallet'], ['mode' => 'legacy'], ['miners' => [['id' => $f->miner, 'name' => 'must not upload']]],
    ['miners' => [['id' => $f->miner], ['id' => $f->other, 'name' => 'extra field']]],
    ['miners' => [['id' => $f->miner], ['id' => $f->miner]]], ['device_token' => str_repeat('a', 33)],
    ['environment' => 'untrusted'],
] as $change) {
    rejects(400, fn() => $f->call('POST', 'register', array_replace($f->registration(), $change)), 'malformed metadata registration rejected');
    check($f->scalar('SELECT COUNT(*) FROM miners') === 1 && !$f->db->inTransaction(), 'bad registration leaves catalog untouched');
}
foreach (['telemetry', 'relay', 'send'] as $retired) {
    rejects(404, fn() => $f->call('POST', $retired, []), 'retired public action rejected without auth: ' . $retired);
}

$f->enable(180);
$due = $f->nextDue();
$f->now += 10;
$f->enable(180);
check($f->nextDue() === $due, 'unchanged save does not postpone next scheduled check');
$repeated = $f->register();
check($repeated['settings']['enabled'] === true && $repeated['settings']['miners'][0]['interval_minutes'] === 180,
    'authenticated re-registration preserves saved opt-in and interval');
foreach ([['enabled' => 1], ['miners' => [['id' => $f->other, 'enabled' => true, 'interval_minutes' => 60]]],
          ['miners' => [['id' => $f->miner, 'enabled' => true, 'interval_minutes' => 1]]],
          ['miners' => [['id' => $f->miner, 'enabled' => true, 'interval_minutes' => 60, 'name' => 'private']]]
          ] as $change) {
    rejects(400, fn() => $f->call('PUT', 'preferences', array_replace($f->schedule(true, 180), $change)), 'invalid preference rejected atomically');
    check($f->call('GET', 'preferences')['settings']['enabled'] === true, 'failed preference leaves master switch unchanged');
}
foreach ([60, 180, 360, 720, 1440] as $interval) {
    $saved = $f->call('PUT', 'preferences', $f->schedule(true, $interval));
    check($saved['settings']['miners'][0]['interval_minutes'] === $interval, 'per-miner interval accepted: ' . $interval);
}

// Build a genuine legacy SQLite schema and verify additive migration and explicit authenticated conversion.
$legacyDB = new PDO('sqlite::memory:');
$legacyDB->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
$legacyDB->exec('PRAGMA foreign_keys=ON');
$legacyDB->exec(<<<'SQL'
CREATE TABLE installations(id TEXT PRIMARY KEY,credential_hash TEXT NOT NULL,relay_hash TEXT,token TEXT NOT NULL,
 token_valid INTEGER NOT NULL DEFAULT 1,token_generation INTEGER NOT NULL DEFAULT 1,environment TEXT NOT NULL,
 enabled INTEGER NOT NULL DEFAULT 0,created INTEGER NOT NULL,updated INTEGER NOT NULL,relay_seen INTEGER,UNIQUE(environment,token));
CREATE TABLE miners(installation TEXT NOT NULL,id TEXT NOT NULL,name TEXT NOT NULL,enabled INTEGER NOT NULL DEFAULT 1,
 interval_minutes INTEGER NOT NULL DEFAULT 60,next_due INTEGER NOT NULL DEFAULT 0,last_sent INTEGER,
 PRIMARY KEY(installation,id),FOREIGN KEY(installation) REFERENCES installations(id) ON DELETE CASCADE);
CREATE TABLE readings(installation TEXT NOT NULL,miner TEXT NOT NULL,observed INTEGER NOT NULL,received INTEGER NOT NULL,source TEXT NOT NULL,
 online INTEGER NOT NULL,hashrate REAL,temperature REAL,power REAL,accepted INTEGER,rejected INTEGER,
 PRIMARY KEY(installation,miner),FOREIGN KEY(installation,miner) REFERENCES miners(installation,id) ON DELETE CASCADE);
CREATE TABLE jobs(id INTEGER PRIMARY KEY,installation TEXT NOT NULL,miner TEXT NOT NULL,token_generation INTEGER NOT NULL,due INTEGER NOT NULL,
 status TEXT NOT NULL DEFAULT 'pending',attempts INTEGER NOT NULL DEFAULT 0,next_attempt INTEGER NOT NULL DEFAULT 0,
 lease_until INTEGER NOT NULL DEFAULT 0,claim TEXT,updated INTEGER NOT NULL,UNIQUE(installation,miner,due,token_generation),
 FOREIGN KEY(installation,miner) REFERENCES miners(installation,id) ON DELETE CASCADE);
CREATE TABLE rate_limits(scope TEXT NOT NULL,slot INTEGER NOT NULL,count INTEGER NOT NULL,PRIMARY KEY(scope,slot));
CREATE TABLE audit(id INTEGER PRIMARY KEY,at INTEGER NOT NULL,kind TEXT NOT NULL,detail TEXT NOT NULL);
SQL);
$legacy = new Fixture(true, $legacyDB, false);
$legacyRelay = FleetAPNs::base64url(random_bytes(32));
$legacyDB->prepare('INSERT INTO installations(id,credential_hash,relay_hash,token,token_valid,token_generation,environment,enabled,created,updated,relay_seen) VALUES(?,?,?,?,1,3,?,1,?,?,?)')->execute([
    $legacy->id, hash('sha256', base64_decode(strtr($legacy->secret, '-_', '+/') . '=')),
    hash('sha256', base64_decode(strtr($legacyRelay, '-_', '+/') . '=')), str_repeat('de', 32), 'sandbox',
    $legacy->now - 900, $legacy->now - 10, $legacy->now - 10]);
$legacyDB->prepare('INSERT INTO miners VALUES(?,?,?,1,180,?,?)')->execute([
    $legacy->id, $legacy->miner, 'Legacy miner name', $legacy->now - 100, $legacy->now - 500]);
$legacyDB->prepare('INSERT INTO readings VALUES(?,?,?,?,?,?,?,?,?,?,?)')->execute([
    $legacy->id, $legacy->miner, $legacy->now, $legacy->now, 'app', 1, 99.0, 45.0, 20.0, 2, 0]);
$legacyDB->prepare("INSERT INTO jobs(installation,miner,token_generation,due,status,updated) VALUES(?,?,3,?,'pending',?)")
    ->execute([$legacy->id, $legacy->miner, $legacy->now - 100, $legacy->now]);
$legacy->service = new FleetService($legacy->config, $legacyDB, fn() => $legacy->now,
    function ($job, $payload) use ($legacy): array { $legacy->sent[] = $payload; return ['status' => 200]; });
check($legacy->scalar("SELECT mode FROM installations WHERE id='" . $legacy->id . "'") === 'legacy_inactive',
    'pre-migration installation is explicitly marked legacy inactive');
check($legacy->scalar('SELECT status FROM jobs') === 'cancelled', 'legacy pending job is retired during additive migration');
check($legacy->service->dispatchDue() === 0 && !$legacy->sent, 'legacy installation cannot create or deliver scheduled checks');
rejects(409, fn() => $legacy->call('GET', 'preferences'), 'legacy admin must explicitly migrate before reading schedule');
rejects(401, fn() => $legacy->call('GET', 'status', null, $legacy->headers($legacyRelay)), 'old relay credential cannot read settings');
check($legacy->scalar('SELECT COUNT(*) FROM readings') === 1, 'legacy reading remains isolated until explicit migration');
$legacy->call('POST', 'register', $legacy->registration(null, [['id' => $legacy->miner]]));
check($legacy->scalar("SELECT mode FROM installations WHERE id='" . $legacy->id . "'") === 'device_check_v1',
    'valid current credential explicitly migrates the installation');
check($legacy->scalar('SELECT COUNT(*) FROM readings') === 0, 'explicit migration clears only that installation legacy readings');
check($legacy->scalar('SELECT relay_hash FROM installations') === null && $legacy->scalar('SELECT relay_seen FROM installations') === null,
    'explicit migration clears legacy relay access and timestamp');
check($legacy->scalar('SELECT enabled FROM installations') === 1 && $legacy->scalar('SELECT interval_minutes FROM miners') === 180,
    'explicit migration preserves saved global and per-miner choices');
check($legacy->scalar('SELECT name FROM miners') === '', 'migration erases old miner display name from cloud metadata');
check($legacy->nextDue() === $legacy->now + 180 * 60, 'migration reschedules from now instead of catching up');
$legacy->due();
check($legacy->service->dispatchDue() === 1 && count($legacy->sent) === 1,
    'migrated schedule becomes eligible without any reading');

// No-readings schedule path and exact generic APNs payload.
$f = new Fixture();
$f->register();
check($f->scalar('SELECT COUNT(*) FROM readings') === 0, 'new registration stores no readings');
check($f->service->dispatchDue() === 0 && $f->scalar('SELECT COUNT(*) FROM jobs') === 0, 'disabled installation creates no jobs');
$f->enable();
check($f->service->dispatchDue() === 0, 'future due time does not send early');
$f->due();
check($f->scalar('SELECT COUNT(*) FROM readings') === 0, 'due eligibility does not require a reading');
check($f->service->dispatchDue() === 1 && count($f->sent) === 1, 'selected due miner emits one check without readings');
check($f->service->dispatchDue() === 0 && count($f->sent) === 1, 'repeat dispatcher does not resend the same interval');
$payload = $f->sent[0];
check($payload['aps']['alert'] === ['title' => 'Scheduled miner check',
    'body' => "Open Hash Fleet on your miners' network to check current readings."], 'push uses exact honest fallback alert');
check($payload['aps']['mutable-content'] === 1 && $payload['aps']['category'] === 'app.hashfleet.summary'
    && $payload['aps']['thread-id'] === 'hashfleet-scheduled-checks', 'push requests extension with stable category and thread');
check($payload['app.hashfleet.deviceID'] === $f->miner && $payload['app.hashfleet.checkVersion'] === 1
    && $payload['app.hashfleet.checkIssuedAt'] === $f->now, 'push contains only selected target UUID, version, and issue time');
$requestID = $payload['app.hashfleet.checkRequestID'];
check(is_string($requestID) && preg_match('/^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/D', $requestID) === 1
    && substr($requestID, 14, 1) === '4' && in_array($requestID[19], ['8', '9', 'a', 'b'], true),
    'request ID is a stable random RFC 4122 version-4 UUID');
check($f->scalar('SELECT request_id FROM jobs') === $requestID, 'request ID is persisted for stable retries');
$payloadJSON = json_encode($payload, JSON_THROW_ON_ERROR);
foreach ([$f->secret, 'Workshop Gamma', 'hashrate', 'temperature', 'power', 'https://', 'Reported offline'] as $forbidden) {
    check(!str_contains($payloadJSON, $forbidden), 'push omits secret/local identity/readings: ' . $forbidden);
}
check($f->scalar('SELECT last_sent FROM miners') === $f->now, 'APNs acceptance recorded as last_sent');
$f = new Fixture(false); $f->register(); $f->enable(); $f->due();
check($f->service->dispatchDue() === 0 && $f->scalar('SELECT COUNT(*) FROM jobs') === 0,
    'unconfigured provider never claims fake delivery');

// Retry/backoff budget, stable request ID, exhausted lease, and non-tight loop.
foreach ([0, 429, 500, 503] as $code) {
    $f = new Fixture(); $f->register(); $f->enable(); $f->due(); $f->response = $code; $f->retryAfter = 1200;
    check($f->service->dispatchDue() === 1, 'retryable response attempted once');
    $firstID = $f->sent[0]['app.hashfleet.checkRequestID'];
    check($f->service->dispatchDue() === 0, 'retryable response has no tight loop');
    $retry = (int)$f->scalar('SELECT next_attempt FROM jobs');
    check($retry >= $f->now + 1200, 'Retry-After and server backoff respected');
    $f->now = $retry; $f->response = 200;
    check($f->service->dispatchDue() === 1 && $f->scalar("SELECT status FROM jobs") === 'sent', 'pending job retries after backoff');
    check($f->sent[1]['app.hashfleet.checkRequestID'] === $firstID, 'retry preserves same opaque request ID');
}
$f = new Fixture(); $f->register(); $f->enable(); $f->due(); $f->response = 500;
$f->service->dispatchDue();
check($f->scalar('SELECT next_attempt FROM jobs') >= $f->now + 900, '5xx waits at least Apple-recommended 15 minutes');
$f = new Fixture(); $f->register(); $f->enable(); $f->due(); $f->response = 429;
for ($attempt = 0; $attempt < 5; $attempt++) {
    $f->service->dispatchDue();
    if ($attempt < 4) $f->now = (int)$f->scalar('SELECT next_attempt FROM jobs');
}
check($f->scalar('SELECT attempts FROM jobs') === 5 && $f->scalar('SELECT status FROM jobs') === 'failed', 'retry budget bounded to five attempts');
check($f->service->dispatchDue() === 0, 'exhausted retry does not spin');
$f = new Fixture(); $f->register(); $f->enable(); $f->due(); $f->response = 429;
$f->service->dispatchDue();
$f->db->exec('UPDATE jobs SET attempts=5,lease_until=' . ($f->now + 90) . ",claim='crashed-final-attempt'");
check($f->service->dispatchDue() === 0, 'active final-attempt lease is left alone');
$f->now += 91;
check($f->service->dispatchDue() === 0 && count($f->sent) === 1, 'expired final lease cannot grant sixth request');
check($f->scalar('SELECT status FROM jobs') === 'failed' && $f->scalar('SELECT attempts FROM jobs') === 5,
    'crashed final attempt is terminal without increasing its budget');
check($f->nextDue() === $f->now + 3600, 'crashed final attempt advances next scheduled interval');
$f->now = $f->nextDue(); $f->response = 200;
check($f->service->dispatchDue() === 1 && count($f->sent) === 2, 'later interval runs after crashed exhausted job');

// Generation-safe invalid token handling, overlapping dispatcher claims, and immediate opt-out.
$f = new Fixture(); $f->register(); $f->enable(); $f->due(); $f->response = 403; $f->service->dispatchDue();
check($f->scalar('SELECT token_valid FROM installations') === 1, 'provider auth failure is not invalid device token');
check($f->scalar('SELECT status FROM jobs') === 'failed', 'provider configuration failure is recorded');
$f = new Fixture(); $f->register(); $f->enable(); $f->due(); $f->response = 410; $f->service->dispatchDue();
check($f->scalar('SELECT token_valid FROM installations') === 0, '410 invalidates matching token generation');
check($f->service->dispatchDue() === 0, 'invalid token is not retried');
$f->call('POST', 'register', $f->registration(str_repeat('cd', 32)));
check($f->scalar('SELECT token_generation FROM installations') === 2 && $f->scalar('SELECT token_valid FROM installations') === 1,
    'new registration refreshes generation');
$f->response = 200;
check($f->service->dispatchDue() === 1, 'new generation is not trapped by old cancelled job');
$f = new Fixture(); $f->register(); $f->enable(); $f->due(); $f->response = 410;
$f->duringSend = function () use ($f) { $f->call('POST', 'register', $f->registration(str_repeat('ef', 32))); };
$f->service->dispatchDue(1);
check($f->scalar('SELECT token_valid FROM installations') === 1 && $f->scalar('SELECT token_generation FROM installations') === 2,
    'late old-generation 410 cannot invalidate refreshed token');
$f = new Fixture(); $f->register(); $f->enable(); $f->due(); $overlap = -1;
$second = new FleetService($f->config, $f->db, fn() => $f->now, static function () { throw new RuntimeException('Duplicate send'); });
$f->duringSend = function () use ($second, &$overlap) { $overlap = $second->dispatchDue(); };
check($f->service->dispatchDue() === 1 && $overlap === 0, 'overlapping dispatcher cannot claim leased job');
check(count($f->sent) === 1, 'one provider request for concurrent dispatchers');
$f->now += 3600; $f->response = 429; $f->duringSend = null; $f->service->dispatchDue();
$f->call('PUT', 'preferences', $f->schedule(false));
$f->now += 300;
check($f->service->dispatchDue() === 0, 'opt-out cancels queued retries before provider request');

// Isolated deletion, retention, and rate-limit privacy.
$f = new Fixture(); $f->register(); $f->enable(); $f->due(); $f->service->dispatchDue();
$f->call('POST', 'register', $f->registration(str_repeat('89', 32)), $f->headers(null, $f->other));
$f->call('DELETE', 'register');
check($f->scalar('SELECT COUNT(*) FROM installations') === 1 && $f->scalar('SELECT COUNT(*) FROM jobs') === 0,
    'delete cascades only authorized installation schedules and jobs');
$f = new Fixture(); $f->register(); $f->now += 7776001; $f->service->purge();
check($f->scalar('SELECT COUNT(*) FROM installations') === 0, 'inactive installation expires after 90 days');
$f = new Fixture(); $f->register();
for ($i = 0; $i < 120; $i++) $f->call('GET', 'status');
rejects(429, fn() => $f->call('GET', 'status'), 'authenticated rate limit enforced');
$f = new Fixture();
for ($i = 0; $i < 180; $i++) $f->service->handle('GET', 'health', [], null, '192.0.2.55');
rejects(429, fn() => $f->service->handle('GET', 'health', [], null, '192.0.2.55'), 'public IP rate limit enforced');
check(!str_contains(json_encode($f->db->query('SELECT * FROM rate_limits')->fetchAll()), '192.0.2.55'),
    'rate storage never contains raw IP address');

// Generate only a temporary fixture P-256 key and independently verify provider JWT behavior.
$directory = sys_get_temp_dir() . '/hashfleet-apns-test-' . bin2hex(random_bytes(6));
mkdir($directory, 0700);
try {
    $key = openssl_pkey_new(['private_key_type' => OPENSSL_KEYTYPE_EC, 'curve_name' => 'prime256v1']);
    openssl_pkey_export($key, $pem); file_put_contents($directory . '/test.p8', $pem); chmod($directory . '/test.p8', 0600);
    $config = ['key_file' => $directory . '/test.p8', 'key_id' => 'ABCDEFGHIJ', 'team_id' => '0123456789',
        'topic' => 'app.hashfleet', 'jwt_cache' => $directory . '/cache.json'];
    $provider = new FleetAPNs($config);
    check($provider->ready(), 'real temporary P-256 test key validates provider prerequisites');
    $jwt = $provider->jwt(1792886400); [$header, $claims, $signature] = explode('.', $jwt);
    $decode = static fn($part) => base64_decode(strtr($part, '-_', '+/') . str_repeat('=', (4 - strlen($part) % 4) % 4), true);
    check(json_decode($decode($header), true) === ['alg' => 'ES256', 'kid' => 'ABCDEFGHIJ'], 'JWT ES256 header is correct');
    check(json_decode($decode($claims), true) === ['iss' => '0123456789', 'iat' => 1792886400], 'JWT issuer and issued-at correct');
    $raw = $decode($signature); check(strlen($raw) === 64, 'JOSE signature exactly 64 bytes');
    $integer = static function ($part) { $part = ltrim($part, "\0") ?: "\0"; if (ord($part[0]) & 0x80) $part = "\0" . $part; return "\x02" . chr(strlen($part)) . $part; };
    $integers = $integer(substr($raw, 0, 32)) . $integer(substr($raw, 32));
    $der = "\x30" . chr(strlen($integers)) . $integers;
    check(openssl_verify($header . '.' . $claims, $der, openssl_pkey_get_details($key)['key'], OPENSSL_ALGO_SHA256) === 1,
        'independent OpenSSL verifies JOSE round trip');
    check((new FleetAPNs($config))->jwt(1792886460) === $jwt, 'separate cron process reuses JWT across minute invocations');
    check($provider->jwt(1792889400) !== $jwt, 'JWT refreshes after 50 minutes');
    check((fileperms($directory . '/cache.json') & 0077) === 0, 'cached provider bearer remains private');
    foreach (["", "\x30\x01\x02", "\x30\x06\x02\x01\xff\x02\x01\x01"] as $bad) {
        $caught = false; try { FleetAPNs::derToJose($bad); } catch (RuntimeException) { $caught = true; }
        check($caught, 'malformed DER is rejected');
    }
    chmod($directory . '/test.p8', 0644); clearstatcache();
    check(!(new FleetAPNs($config))->ready(), 'public-readable APNs private key refused');
} finally {
    foreach (glob($directory . '/*') as $file) unlink($file);
    rmdir($directory);
}

// Focused collaborator boundary: schedule validation completes before any write transaction or mutation.
$boundary = new Fixture();
$boundary->register();
$invalidSchedule = $boundary->schedule(true, 61);
rejects(400, fn() => $boundary->call('PUT', 'preferences', $invalidSchedule),
    'preference writer rejects intervals outside the supported schedule set');
check(!$boundary->db->inTransaction() && (int)$boundary->scalar('SELECT interval_minutes FROM miners') === 60,
    'invalid preference schedule leaves storage unchanged and transaction closed');
fwrite(STDOUT, "PASS: {$checks} backend checks. No APNs requests or miner access.\n");
