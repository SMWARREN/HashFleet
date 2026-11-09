<?php
declare(strict_types=1);
// Production: ~/hashfleet-private/config.php, owned by the site account, mode 0600.
// Leave key_id/team_id/key_file null until a genuine APNs key is securely installed.
return [
    'database' => __DIR__ . '/hashfleet.sqlite',
    'privacy_salt' => 'REPLACE_WITH_32_RANDOM_BYTES_ENCODED_AS_HEX',
    'allow_local_http' => false,
    'apns' => [
        'key_file' => null,
        'key_id' => null,
        'team_id' => null,
        'topic' => 'app.hashfleet',
        'jwt_cache' => __DIR__ . '/apns-jwt.json',
    ],
];
