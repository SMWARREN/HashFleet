<?php
declare(strict_types=1);
require_once __DIR__ . '/APNs.php';

final class FleetHttpError extends RuntimeException {
    public function __construct(public readonly int $status, string $message) { parent::__construct($message); }
}

/** Installation-scoped schedule storage. Keep this directory outside the public webroot. */
final class FleetService {
    private PDO $db;
    private FleetAPNs $provider;
    private Closure $clock;
    private ?Closure $sender;
    private const MODE = 'device_check_v1';
    private const INTERVALS = [60, 180, 360, 720, 1440];

    public function __construct(private array $config, ?PDO $db = null, ?Closure $clock = null, ?Closure $sender = null) {
        $this->db = $db ?? new PDO('sqlite:' . $config['database']);
        $this->db->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
        $this->db->setAttribute(PDO::ATTR_DEFAULT_FETCH_MODE, PDO::FETCH_ASSOC);
        $this->db->exec('PRAGMA foreign_keys=ON; PRAGMA busy_timeout=5000;');
        $this->clock = $clock ?? static fn(): int => time();
        $this->sender = $sender; // Offline test injection only. Never derived from HTTP input.
        $this->provider = new FleetAPNs($config['apns'] ?? []);
        $this->migrateSchema();
    }

    private function migrateSchema(): void {
        $this->db->exec(<<<'SQL'
CREATE TABLE IF NOT EXISTS installations(
 id TEXT PRIMARY KEY, credential_hash TEXT NOT NULL, relay_hash TEXT,
 token TEXT NOT NULL, token_valid INTEGER NOT NULL DEFAULT 1, token_generation INTEGER NOT NULL DEFAULT 1,
 environment TEXT NOT NULL, enabled INTEGER NOT NULL DEFAULT 0, created INTEGER NOT NULL, updated INTEGER NOT NULL,
 relay_seen INTEGER, mode TEXT NOT NULL DEFAULT 'legacy_inactive', UNIQUE(environment,token));
CREATE TABLE IF NOT EXISTS miners(
 installation TEXT NOT NULL, id TEXT NOT NULL, name TEXT NOT NULL DEFAULT '', enabled INTEGER NOT NULL DEFAULT 1,
 interval_minutes INTEGER NOT NULL DEFAULT 60, next_due INTEGER NOT NULL DEFAULT 0, last_sent INTEGER,
 PRIMARY KEY(installation,id), FOREIGN KEY(installation) REFERENCES installations(id) ON DELETE CASCADE);
-- Retained only so additive upgrades can safely clear legacy samples and expire untouched legacy rows.
CREATE TABLE IF NOT EXISTS readings(
 installation TEXT NOT NULL, miner TEXT NOT NULL, observed INTEGER NOT NULL, received INTEGER NOT NULL,
 source TEXT NOT NULL, online INTEGER NOT NULL, hashrate REAL, temperature REAL, power REAL, accepted INTEGER, rejected INTEGER,
 PRIMARY KEY(installation,miner), FOREIGN KEY(installation,miner) REFERENCES miners(installation,id) ON DELETE CASCADE);
CREATE TABLE IF NOT EXISTS jobs(
 id INTEGER PRIMARY KEY, installation TEXT NOT NULL, miner TEXT NOT NULL, token_generation INTEGER NOT NULL,
 due INTEGER NOT NULL, status TEXT NOT NULL DEFAULT 'pending', attempts INTEGER NOT NULL DEFAULT 0,
 next_attempt INTEGER NOT NULL DEFAULT 0, lease_until INTEGER NOT NULL DEFAULT 0, claim TEXT, updated INTEGER NOT NULL,
 request_id TEXT, UNIQUE(installation,miner,due,token_generation),
 FOREIGN KEY(installation,miner) REFERENCES miners(installation,id) ON DELETE CASCADE);
CREATE TABLE IF NOT EXISTS rate_limits(scope TEXT NOT NULL, slot INTEGER NOT NULL, count INTEGER NOT NULL,
 PRIMARY KEY(scope,slot));
CREATE TABLE IF NOT EXISTS audit(id INTEGER PRIMARY KEY, at INTEGER NOT NULL, kind TEXT NOT NULL, detail TEXT NOT NULL);
SQL);
        $this->addColumnIfMissing('installations', 'mode', "TEXT NOT NULL DEFAULT 'legacy_inactive'");
        $this->addColumnIfMissing('jobs', 'request_id', 'TEXT');
        foreach ($this->query('SELECT id FROM jobs WHERE request_id IS NULL')->fetchAll(PDO::FETCH_COLUMN) as $id) {
            $this->query('UPDATE jobs SET request_id=? WHERE id=?', [self::requestUUID(), $id]);
        }
        // Queued jobs created by the retired telemetry/relay service must never leak into dispatch.
        $this->query("UPDATE jobs SET status='cancelled',lease_until=0,claim=NULL,updated=?
            WHERE status='pending' AND installation IN (SELECT id FROM installations WHERE mode<>?)", [$this->now(), self::MODE]);
    }

    private function addColumnIfMissing(string $table, string $column, string $definition): void {
        $columns = $this->query("PRAGMA table_info(" . $table . ")")->fetchAll();
        foreach ($columns as $info) if ($info['name'] === $column) return;
        $this->db->exec("ALTER TABLE {$table} ADD COLUMN {$column} {$definition}");
    }

    private function now(): int { return ($this->clock)(); }
    public function providerReady(): bool { return $this->provider->ready(); }
    private static function fail(int $status, string $message): never { throw new FleetHttpError($status, $message); }
    private function query(string $sql, array $params = []): PDOStatement {
        $statement = $this->db->prepare($sql);
        $statement->execute($params);
        return $statement;
    }
    private function transaction(Closure $work): mixed {
        $this->db->beginTransaction();
        try {
            // Acquire SQLite's write reservation before inspecting ownership or job claims.
            $this->db->exec('UPDATE installations SET updated=updated WHERE 0');
            $result = $work();
            $this->db->commit();
            return $result;
        } catch (Throwable $error) {
            if ($this->db->inTransaction()) $this->db->rollBack();
            throw $error;
        }
    }

    public static function decodeBody(string $raw): array {
        if (strlen($raw) > 131072) self::fail(413, 'Request is too large.');
        try {
            $object = json_decode($raw, false, 24, JSON_THROW_ON_ERROR);
            if (!$object instanceof stdClass) self::fail(400, 'Expected a JSON object.');
            return json_decode($raw, true, 24, JSON_THROW_ON_ERROR);
        } catch (JsonException) { self::fail(400, 'Invalid JSON.'); }
    }
    private static function keys(mixed $value, array $required): array {
        if (!is_array($value) || array_diff(array_keys($value), $required) || array_diff($required, array_keys($value))) {
            self::fail(400, 'Unknown or missing fields.');
        }
        return $value;
    }
    private static function items(mixed $value): array {
        if (!is_array($value) || !array_is_list($value) || count($value) > 64) self::fail(400, 'Invalid miner list.');
        return $value;
    }
    private static function uuid(mixed $value): string {
        if (!is_string($value) || !preg_match('/^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/D', $value)) {
            self::fail(400, 'Invalid installation or miner ID.');
        }
        return $value;
    }
    private static function requestUUID(): string {
        $bytes = random_bytes(16);
        $bytes[6] = chr((ord($bytes[6]) & 0x0f) | 0x40);
        $bytes[8] = chr((ord($bytes[8]) & 0x3f) | 0x80);
        $hex = bin2hex($bytes);
        return substr($hex, 0, 8) . '-' . substr($hex, 8, 4) . '-' . substr($hex, 12, 4) . '-'
            . substr($hex, 16, 4) . '-' . substr($hex, 20);
    }
    private static function credentialHash(mixed $value): ?string {
        if (!is_string($value) || !preg_match('/^[A-Za-z0-9_-]{43}$/D', $value)) return null;
        $raw = base64_decode(strtr($value, '-_', '+/') . '=', true);
        if ($raw === false || strlen($raw) !== 32 || FleetAPNs::base64url($raw) !== $value) return null;
        return hash('sha256', $raw);
    }
    private static function bearer(array $headers): string {
        if (!preg_match('/^Bearer ([A-Za-z0-9_-]{43})$/D', (string)($headers['authorization'] ?? ''), $matches)
            || !($hash = self::credentialHash($matches[1]))) self::fail(401, 'Unauthorized.');
        return $hash;
    }
    private function authenticate(string $id, array $headers): array {
        $hash = self::bearer($headers);
        $row = $this->query('SELECT * FROM installations WHERE id=?', [$id])->fetch();
        if (!$row || !hash_equals($row['credential_hash'], $hash)) self::fail(401, 'Unauthorized.');
        return $row;
    }
    private function requireDeviceMode(array $installation): void {
        if (($installation['mode'] ?? 'legacy_inactive') !== self::MODE) self::fail(409, 'Explicit device_check_v1 registration is required.');
    }
    private function limit(string $scope, int $window, int $maximum): void {
        $slot = intdiv($this->now(), $window);
        $this->query('INSERT INTO rate_limits VALUES(?,?,1) ON CONFLICT(scope,slot) DO UPDATE SET count=count+1', [$scope, $slot]);
        $count = $this->query('SELECT count FROM rate_limits WHERE scope=? AND slot=?', [$scope, $slot])->fetchColumn();
        if ($count > $maximum) self::fail(429, 'Too many requests. Try again later.');
    }
    private function settings(string $id): array {
        $enabled = (bool)$this->query('SELECT enabled FROM installations WHERE id=?', [$id])->fetchColumn();
        $miners = $this->query('SELECT id,enabled,interval_minutes FROM miners WHERE installation=? ORDER BY id', [$id])->fetchAll();
        return ['enabled' => $enabled, 'miners' => array_map(static fn($row) => [
            'id' => $row['id'], 'enabled' => (bool)$row['enabled'], 'interval_minutes' => (int)$row['interval_minutes']], $miners)];
    }
    private function wrapper(string $id): array {
        return ['ok' => true, 'mode' => self::MODE, 'provider_ready' => $this->providerReady(), 'settings' => $this->settings($id)];
    }

    public function handle(string $method, string $action, array $headers, ?array $body = null, string $clientIP = ''): array {
        // Never trust forwarded headers. Persist only a salted hash of the peer address.
        $ipScope = hash('sha256', ($this->config['privacy_salt'] ?? '') . $clientIP);
        $this->limit('ip:' . $ipScope, 60, 180);
        if (!in_array($action, ['health', 'register', 'preferences', 'status'], true)) self::fail(404, 'Not found.');
        $allowedMethods = ['health' => ['GET'], 'register' => ['POST', 'DELETE'],
            'preferences' => ['GET', 'PUT'], 'status' => ['GET']];
        if (!in_array($method, $allowedMethods[$action], true)) self::fail(405, 'Method not allowed.');
        if ($action === 'health') return ['ok' => true, 'service' => 'hashfleet-notifications',
            'mode' => self::MODE, 'provider_ready' => $this->providerReady()];

        $id = self::uuid($headers['x-hashfleet-installation'] ?? null);
        if ($action === 'register' && $method === 'POST') {
            return $this->registration($id, $headers, self::keys($body, ['mode', 'device_token', 'environment', 'miners']), $ipScope);
        }
        $installation = $this->authenticate($id, $headers);
        $this->limit('installation:' . $id, 60, 120);
        if ($action === 'register' && $method === 'DELETE') {
            $this->query('DELETE FROM installations WHERE id=?', [$id]);
            return ['ok' => true];
        }
        $this->requireDeviceMode($installation);
        if ($action === 'preferences' && $method === 'GET') return $this->wrapper($id);
        if ($action === 'status') return $this->status($id);
        return $this->preferences($installation, self::keys($body, ['enabled', 'miners']));
    }

    private function registration(string $id, array $headers, array $body, string $ipScope): array {
        if ($body['mode'] !== self::MODE) self::fail(400, 'Unsupported registration mode.');
        $token = $body['device_token'];
        $environment = $body['environment'];
        if (!is_string($token) || !preg_match('/^[a-fA-F0-9]{32,512}$/D', $token) || strlen($token) % 2
            || !in_array($environment, ['sandbox', 'production'], true)) self::fail(400, 'Invalid registration.');
        $token = strtolower($token);
        $credential = self::bearer($headers);
        $miners = [];
        $seen = [];
        foreach (self::items($body['miners']) as $miner) {
            self::keys($miner, ['id']);
            $minerID = self::uuid($miner['id']);
            if (isset($seen[$minerID])) self::fail(400, 'Duplicate miner.');
            $seen[$minerID] = true;
            $miners[] = $minerID;
        }
        $exists = $this->query('SELECT 1 FROM installations WHERE id=?', [$id])->fetchColumn();
        if (!$exists) $this->limit('enroll:' . $ipScope, 3600, 10);
        else $this->limit('installation:' . $id, 60, 120);

        $this->transaction(function () use ($id, $headers, $credential, $token, $environment, $miners) {
            $existing = $this->query('SELECT * FROM installations WHERE id=?', [$id])->fetch() ?: null;
            if ($existing) $this->authenticate($id, $headers);
            $owner = $this->query('SELECT id FROM installations WHERE environment=? AND token=? AND id<>?',
                [$environment, $token, $id])->fetchColumn();
            if ($owner) self::fail(409, 'This device token is already enrolled.');

            $migrating = $existing !== null && ($existing['mode'] ?? 'legacy_inactive') !== self::MODE;
            $rotated = $existing !== null && ($existing['token'] !== $token || $existing['environment'] !== $environment
                || !$existing['token_valid'] || $migrating);
            if ($existing) {
                $this->query('UPDATE installations SET mode=?,token=?,environment=?,token_valid=1,token_generation=token_generation+?,updated=? WHERE id=?',
                    [self::MODE, $token, $environment, $rotated ? 1 : 0, $this->now(), $id]);
                if ($rotated || $migrating) $this->cancelJobs($id);
                if ($migrating) {
                    // Explicit authenticated opt-in is the only path that clears legacy telemetry and relay access.
                    $this->query('DELETE FROM readings WHERE installation=?', [$id]);
                    $this->query('UPDATE installations SET relay_hash=NULL,relay_seen=NULL WHERE id=?', [$id]);
                    $this->query("UPDATE miners SET name='',next_due=? + interval_minutes * 60,last_sent=NULL WHERE installation=?",
                        [$this->now(), $id]);
                }
            } else {
                $this->query('INSERT INTO installations(id,credential_hash,relay_hash,token,token_valid,token_generation,environment,enabled,created,updated,relay_seen,mode)
                    VALUES(?,?,NULL,?,1,1,?,0,?,?,NULL,?)', [$id, $credential, $token, $environment, $this->now(), $this->now(), self::MODE]);
            }

            foreach ($miners as $minerID) {
                $this->query("INSERT INTO miners(installation,id,name,enabled,interval_minutes,next_due)
                    VALUES(?,?,'',1,60,?) ON CONFLICT(installation,id) DO UPDATE SET name=''",
                    [$id, $minerID, $this->now() + 3600]);
            }
            foreach ($this->query('SELECT id FROM miners WHERE installation=?', [$id])->fetchAll(PDO::FETCH_COLUMN) as $minerID) {
                if (!in_array($minerID, $miners, true)) $this->query('DELETE FROM miners WHERE installation=? AND id=?', [$id, $minerID]);
            }
        });
        return $this->wrapper($id);
    }

    private function cancelJobs(string $id, ?string $miner = null): void {
        $sql = "UPDATE jobs SET status='cancelled',lease_until=0,claim=NULL,updated=? WHERE installation=? AND status='pending'";
        $params = [$this->now(), $id];
        if ($miner !== null) { $sql .= ' AND miner=?'; $params[] = $miner; }
        $this->query($sql, $params);
    }

    private function preferences(array $installation, array $body): array {
        if (!is_bool($body['enabled'])) self::fail(400, 'Invalid enabled setting.');
        $id = $installation['id'];
        $current = [];
        foreach ($this->settings($id)['miners'] as $miner) $current[$miner['id']] = $miner;
        $miners = [];
        $seen = [];
        foreach (self::items($body['miners']) as $miner) {
            self::keys($miner, ['id', 'enabled', 'interval_minutes']);
            $minerID = self::uuid($miner['id']);
            if (!isset($current[$minerID]) || isset($seen[$minerID])) self::fail(400, 'Unknown or duplicate miner.');
            if (!is_bool($miner['enabled']) || !in_array($miner['interval_minutes'], self::INTERVALS, true)) {
                self::fail(400, 'Invalid miner schedule.');
            }
            $seen[$minerID] = true;
            $miners[] = ['id' => $minerID, 'enabled' => $miner['enabled'], 'interval_minutes' => $miner['interval_minutes']];
        }
        $this->transaction(function () use ($id, $installation, $body, $current, $miners, $seen) {
            $this->query('UPDATE installations SET enabled=?,updated=? WHERE id=?', [$body['enabled'] ? 1 : 0, $this->now(), $id]);
            if (!$body['enabled']) $this->cancelJobs($id);
            foreach ($miners as $miner) {
                $old = $current[$miner['id']];
                $reschedule = (!$installation['enabled'] && $body['enabled'])
                    || $old['enabled'] !== $miner['enabled'] || $old['interval_minutes'] !== $miner['interval_minutes'];
                if ($reschedule) $this->cancelJobs($id, $miner['id']);
                $this->query('UPDATE miners SET name=\'\',enabled=?,interval_minutes=?' . ($reschedule ? ',next_due=?' : '')
                    . ' WHERE installation=? AND id=?', $reschedule
                        ? [$miner['enabled'] ? 1 : 0, $miner['interval_minutes'], $this->now() + $miner['interval_minutes'] * 60, $id, $miner['id']]
                        : [$miner['enabled'] ? 1 : 0, $miner['interval_minutes'], $id, $miner['id']]);
            }
            foreach (array_keys($current) as $minerID) {
                if (!isset($seen[$minerID])) {
                    $this->cancelJobs($id, $minerID);
                    $this->query('DELETE FROM miners WHERE installation=? AND id=?', [$id, $minerID]);
                }
            }
        });
        return $this->wrapper($id);
    }

    private static function iso(mixed $time): ?string { return $time === null ? null : gmdate('Y-m-d\TH:i:s\Z', (int)$time); }
    private function status(string $id): array {
        $rows = $this->query('SELECT id,enabled,interval_minutes,next_due,last_sent FROM miners WHERE installation=? ORDER BY id', [$id])->fetchAll();
        $schedules = array_map(static fn($row) => ['id' => $row['id'], 'enabled' => (bool)$row['enabled'],
            'interval_minutes' => (int)$row['interval_minutes'], 'next_due' => self::iso($row['next_due']),
            'last_sent' => self::iso($row['last_sent'])], $rows);
        $tokenValid = (bool)$this->query('SELECT token_valid FROM installations WHERE id=?', [$id])->fetchColumn();
        return $this->wrapper($id) + ['token_valid' => $tokenValid, 'schedules' => $schedules];
    }

    /** Claim each due selected miner transactionally. Readings are intentionally not part of eligibility. */
    public function dispatchDue(int $maximum = 50): int {
        $this->purge();
        if ($this->sender === null && !$this->providerReady()) return 0;
        $now = $this->now();
        $attempted = 0;
        $this->transaction(function () use ($now) {
            $exhausted = $this->query("SELECT j.id,j.installation,j.miner,j.due,m.interval_minutes
                FROM jobs j JOIN installations i ON i.id=j.installation
                JOIN miners m ON m.installation=j.installation AND m.id=j.miner
                WHERE i.mode=? AND j.status='pending' AND j.attempts>=5 AND j.lease_until<=?", [self::MODE, $now])->fetchAll();
            foreach ($exhausted as $job) {
                $this->query("UPDATE jobs SET status='failed',claim=NULL,lease_until=0,updated=? WHERE id=?", [$now, $job['id']]);
                $this->query('UPDATE miners SET next_due=? WHERE installation=? AND id=? AND next_due=?',
                    [$now + $job['interval_minutes'] * 60, $job['installation'], $job['miner'], $job['due']]);
            }
            $due = $this->query('SELECT i.id installation,i.token_generation,m.id miner,m.next_due
                FROM installations i JOIN miners m ON m.installation=i.id
                WHERE i.mode=? AND i.enabled=1 AND i.token_valid=1 AND m.enabled=1 AND m.next_due<=?',
                [self::MODE, $now])->fetchAll();
            foreach ($due as $job) {
                $requestID = self::requestUUID();
                $this->query("INSERT INTO jobs(installation,miner,token_generation,due,updated,request_id) VALUES(?,?,?,?,?,?)
                    ON CONFLICT(installation,miner,due,token_generation) DO UPDATE SET status='pending',attempts=0,next_attempt=0,
                    lease_until=0,claim=NULL,updated=excluded.updated,request_id=excluded.request_id WHERE jobs.status='cancelled'",
                    [$job['installation'], $job['miner'], $job['token_generation'], $job['next_due'], $now, $requestID]);
            }
        });
        for ($iteration = 0; $iteration < max(0, min(100, $maximum)); $iteration++) {
            $job = $this->transaction(function () use ($now) {
                $job = $this->query("SELECT j.*,i.token,i.environment,i.enabled installation_enabled,i.token_valid,
                    i.token_generation current_generation,i.mode,m.enabled miner_enabled,m.interval_minutes,m.next_due
                    FROM jobs j JOIN installations i ON i.id=j.installation
                    JOIN miners m ON m.installation=j.installation AND m.id=j.miner
                    WHERE i.mode=? AND j.status='pending' AND j.attempts<5 AND j.next_attempt<=? AND j.lease_until<=?
                    ORDER BY j.id LIMIT 1", [self::MODE, $now, $now])->fetch();
                if (!$job) return null;
                $claim = bin2hex(random_bytes(16));
                $changed = $this->query("UPDATE jobs SET lease_until=?,claim=?,attempts=attempts+1,updated=?
                    WHERE id=? AND status='pending' AND attempts<5 AND lease_until<=?", [$now + 90, $claim, $now, $job['id'], $now])->rowCount();
                if (!$changed) return null;
                $job['claim'] = $claim;
                $job['attempts'] = (int)$job['attempts'] + 1;
                return $job;
            });
            if ($job === null) break;
            if (!$job['installation_enabled'] || !$job['miner_enabled'] || !$job['token_valid']
                || $job['token_generation'] !== $job['current_generation']) {
                $this->finish($job, 'cancelled', $now);
                continue;
            }
            // Recheck opt-out, catalog membership, generation, and claim immediately before provider I/O.
            $eligible = $this->query("SELECT 1 FROM jobs j JOIN installations i ON i.id=j.installation
                JOIN miners m ON m.installation=j.installation AND m.id=j.miner
                WHERE j.id=? AND j.claim=? AND j.status='pending' AND i.mode=? AND i.enabled=1 AND i.token_valid=1
                AND i.token_generation=j.token_generation AND m.enabled=1 AND m.next_due=j.due",
                [$job['id'], $job['claim'], self::MODE])->fetchColumn();
            if (!$eligible) continue;
            try { $response = $this->sender ? ($this->sender)($job, $this->payload($job), $now)
                : $this->provider->send($job, $this->payload($job), $now); }
            catch (Throwable) { $response = ['status' => 0, 'reason' => 'TransportUnavailable']; }
            $attempted++;
            $status = (int)($response['status'] ?? 0);
            if ($status === 200) {
                $this->finish($job, 'sent', $now);
            } elseif ($status === 410) {
                $this->transaction(function () use ($job, $now) {
                    // A late 410 cannot invalidate a refreshed token or a different wire-mode installation.
                    $changed = $this->query('UPDATE installations SET token_valid=0,updated=? WHERE id=? AND mode=? AND token_generation=? AND token=?',
                        [$now, $job['installation'], self::MODE, $job['token_generation'], $job['token']])->rowCount();
                    $this->query("UPDATE jobs SET status='invalid_token',claim=NULL,lease_until=0,updated=? WHERE id=? AND claim=?",
                        [$now, $job['id'], $job['claim']]);
                    if ($changed) $this->cancelJobs($job['installation']);
                });
                $this->audit('invalid_token', '410');
            } elseif (($status === 0 || $status === 429 || $status >= 500) && $job['attempts'] < 5) {
                $delay = max($status >= 500 ? 900 : 60, min(3600, 60 * (2 ** ($job['attempts'] - 1))),
                    min(3600, max(0, (int)($response['retry_after'] ?? 0))));
                $this->query('UPDATE jobs SET next_attempt=?,lease_until=0,claim=NULL,updated=? WHERE id=? AND claim=? AND status=\'pending\'',
                    [$now + $delay, $now, $job['id'], $job['claim']]);
                $this->audit('retry', (string)$status);
            } else {
                $this->finish($job, 'failed', $now);
                $this->audit('provider_error', (string)$status);
            }
        }
        $this->purge();
        return $attempted;
    }

    private function finish(array $job, string $status, int $now): void {
        $this->transaction(function () use ($job, $status, $now) {
            $changed = $this->query('UPDATE jobs SET status=?,lease_until=0,claim=NULL,updated=? WHERE id=? AND claim=? AND status=\'pending\'',
                [$status, $now, $job['id'], $job['claim']])->rowCount();
            if ($changed) {
                $sql = 'UPDATE miners SET next_due=?' . ($status === 'sent' ? ',last_sent=?' : '') . ' WHERE installation=? AND id=? AND next_due=?';
                $params = [$now + $job['interval_minutes'] * 60];
                if ($status === 'sent') $params[] = $now;
                $this->query($sql . ' AND EXISTS(SELECT 1 FROM installations i WHERE i.id=miners.installation AND i.mode=?)',
                    [...$params, $job['installation'], $job['miner'], $job['due'], self::MODE]);
            }
        });
    }

    private function payload(array $job): array {
        return ['aps' => ['alert' => ['title' => 'Scheduled miner check',
                'body' => "Open Hash Fleet on your miners' network to check current readings."],
            'mutable-content' => 1, 'category' => 'app.hashfleet.summary', 'thread-id' => 'hashfleet-scheduled-checks'],
            'app.hashfleet.deviceID' => $job['miner'], 'app.hashfleet.checkVersion' => 1,
            'app.hashfleet.checkIssuedAt' => (int)$this->now(), 'app.hashfleet.checkRequestID' => $job['request_id']];
    }

    private function audit(string $kind, string $detail): void {
        $this->query('INSERT INTO audit(at,kind,detail) VALUES(?,?,?)', [$this->now(), $kind, $detail]);
    }
    public function purge(): void {
        $this->query("DELETE FROM jobs WHERE status<>'pending' AND updated<?", [$this->now() - 604800]);
        // This table is migration-only after device_check_v1 registration and is never written by HTTP.
        $this->query('DELETE FROM readings WHERE observed<?', [$this->now() - 86400]);
        $this->query('DELETE FROM audit WHERE at<?', [$this->now() - 604800]);
        $this->query("DELETE FROM rate_limits WHERE (scope LIKE 'enroll:%' AND slot<?) OR (scope NOT LIKE 'enroll:%' AND slot<?)",
            [intdiv($this->now(), 3600) - 1, intdiv($this->now(), 60) - 60]);
        $this->query('DELETE FROM installations WHERE updated<?', [$this->now() - 7776000]);
    }
}
