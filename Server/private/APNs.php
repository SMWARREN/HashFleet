<?php
declare(strict_types=1);

/** Private APNs transport. Fixed Apple endpoints, topic, TLS and HTTP/2 only. */
final class FleetAPNs {
    private ?OpenSSLAsymmetricKey $key = null;

    public function __construct(private array $config) {}

    public function ready(): bool {
        $c = $this->config;
        if (!preg_match('/^[A-Z0-9]{10}$/D', (string)($c['key_id'] ?? ''))
            || !preg_match('/^[A-Z0-9]{10}$/D', (string)($c['team_id'] ?? ''))
            || ($c['topic'] ?? '') !== 'app.hashfleet'
            || !is_file($c['key_file'] ?? '') || !is_readable($c['key_file'])
            || ((fileperms($c['key_file']) & 0077) !== 0)
            || !function_exists('curl_version')
            || !(curl_version()['features'] & CURL_VERSION_HTTP2)) return false;
        $key = @openssl_pkey_get_private('file://' . $c['key_file']);
        $details = $key ? openssl_pkey_get_details($key) : false;
        if (!$details || ($details['type'] ?? null) !== OPENSSL_KEYTYPE_EC
            || ($details['ec']['curve_name'] ?? '') !== 'prime256v1') return false;
        $this->key = $key;
        return true;
    }

    public static function base64url(string $value): string {
        return rtrim(strtr(base64_encode($value), '+/', '-_'), '=');
    }

    /** Strict DER ECDSA P-256 signature to the 64-byte JOSE R || S form. */
    public static function derToJose(string $der): string {
        $offset = 0;
        $byte = static function () use ($der, &$offset): int {
            if ($offset >= strlen($der)) throw new RuntimeException('Invalid signature');
            return ord($der[$offset++]);
        };
        if ($byte() !== 0x30 || $byte() !== strlen($der) - 2) {
            throw new RuntimeException('Invalid signature');
        }
        $result = '';
        for ($part = 0; $part < 2; $part++) {
            if ($byte() !== 0x02) throw new RuntimeException('Invalid signature');
            $length = $byte();
            if ($length < 1 || $length > 33 || $offset + $length > strlen($der)) {
                throw new RuntimeException('Invalid signature');
            }
            $integer = substr($der, $offset, $length);
            $offset += $length;
            if (ord($integer[0]) & 0x80) throw new RuntimeException('Invalid signature');
            $integer = ltrim($integer, "\0");
            if (strlen($integer) > 32) throw new RuntimeException('Invalid signature');
            $result .= str_pad($integer, 32, "\0", STR_PAD_LEFT);
        }
        if ($offset !== strlen($der)) throw new RuntimeException('Invalid signature');
        return $result;
    }

    public function jwt(int $now): string {
        if (!$this->ready()) throw new RuntimeException('Provider is not configured');
        // Reuse the same token across minute-by-minute cron processes. Never put this cache in webroot.
        $path = $this->config['jwt_cache'];
        $file = fopen($path, 'c+');
        if (!$file) throw new RuntimeException('Provider cache is unavailable');
        chmod($path, 0600);
        try {
            if (!flock($file, LOCK_EX)) throw new RuntimeException('Provider cache is unavailable');
            $fingerprint = hash('sha256', file_get_contents($this->config['key_file'])
                . $this->config['key_id'] . $this->config['team_id']);
            $cached = json_decode(stream_get_contents($file, 8192) ?: '{}', true);
            if (is_array($cached) && ($cached['fingerprint'] ?? '') === $fingerprint
                && is_int($cached['issued'] ?? null) && $cached['issued'] <= $now
                && $now - $cached['issued'] < 3000 && is_string($cached['token'] ?? null)) {
                return $cached['token'];
            }
            $header = self::base64url(json_encode(['alg' => 'ES256', 'kid' => $this->config['key_id']], JSON_THROW_ON_ERROR));
            $claims = self::base64url(json_encode(['iss' => $this->config['team_id'], 'iat' => $now], JSON_THROW_ON_ERROR));
            $message = $header . '.' . $claims;
            if (!openssl_sign($message, $der, $this->key, OPENSSL_ALGO_SHA256)) {
                throw new RuntimeException('Provider signing failed');
            }
            $token = $message . '.' . self::base64url(self::derToJose($der));
            rewind($file);
            ftruncate($file, 0);
            fwrite($file, json_encode(['fingerprint' => $fingerprint, 'issued' => $now, 'token' => $token], JSON_THROW_ON_ERROR));
            fflush($file);
            return $token;
        } finally { flock($file, LOCK_UN); fclose($file); }
    }

    public function send(array $job, array $payload, int $now): array {
        $host = $job['environment'] === 'sandbox' ? 'api.sandbox.push.apple.com' : 'api.push.apple.com';
        if (!preg_match('/^[a-f0-9]{32,512}$/D', $job['token']) || strlen($job['token']) % 2) {
            throw new RuntimeException('Invalid stored token');
        }
        $json = json_encode($payload, JSON_THROW_ON_ERROR | JSON_UNESCAPED_UNICODE);
        if (strlen($json) > 4096) throw new RuntimeException('Payload exceeds APNs limit');
        $retryAfter = 0;
        $response = '';
        $curl = curl_init('https://' . $host . '/3/device/' . $job['token']);
        curl_setopt_array($curl, [
            CURLOPT_POST => true, CURLOPT_POSTFIELDS => $json,
            CURLOPT_HTTP_VERSION => CURL_HTTP_VERSION_2_0,
            CURLOPT_SSL_VERIFYPEER => true, CURLOPT_SSL_VERIFYHOST => 2,
            CURLOPT_PROTOCOLS => CURLPROTO_HTTPS, CURLOPT_FOLLOWLOCATION => false,
            CURLOPT_PROXY => '', CURLOPT_CONNECTTIMEOUT => 8, CURLOPT_TIMEOUT => 20,
            CURLOPT_HTTPHEADER => [
                'authorization: bearer ' . $this->jwt($now), 'content-type: application/json',
                'apns-topic: app.hashfleet', 'apns-push-type: alert', 'apns-priority: 5',
                'apns-expiration: ' . ($now + 300),
                'apns-collapse-id: ' . hash('sha256', $job['installation'] . ':' . $job['miner']),
            ],
            CURLOPT_HEADERFUNCTION => static function ($handle, string $header) use (&$retryAfter, $now): int {
                if (stripos($header, 'retry-after:') === 0) {
                    $value = trim(substr($header, 12));
                    $seconds = ctype_digit($value) ? (int)$value : max(0, (strtotime($value) ?: $now) - $now);
                    $retryAfter = min(3600, $seconds);
                }
                return strlen($header);
            },
            CURLOPT_WRITEFUNCTION => static function ($handle, string $data) use (&$response): int {
                if (strlen($response) + strlen($data) > 8192) return 0;
                $response .= $data;
                return strlen($data);
            },
        ]);
        $result = curl_exec($curl);
        $status = $result === false ? 0 : (int)curl_getinfo($curl, CURLINFO_RESPONSE_CODE);
        if ((int)curl_getinfo($curl, CURLINFO_HTTP_VERSION) !== CURL_HTTP_VERSION_2_0) $status = 0;
        curl_close($curl);
        $decoded = json_decode($response, true);
        $reason = is_array($decoded) && is_string($decoded['reason'] ?? null) ? $decoded['reason'] : '';
        return ['status' => $status, 'reason' => preg_replace('/[^A-Za-z0-9]/', '', substr($reason, 0, 64)),
            'retry_after' => $retryAfter];
    }
}
