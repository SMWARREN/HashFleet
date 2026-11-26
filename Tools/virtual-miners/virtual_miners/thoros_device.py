"""Stateful synthetic Hammer ThorOS device for the API fixture backend.

Field names and write semantics follow the official "THOR Miner Complete API
Reference" V1.0.0 (firmware v2.0.0). Values are synthetic. Telemetry is derived
from the current settings so a client can see the effect of a change:
hashrate tracks frequency, power tracks frequency and core voltage, board
temperature tracks power and fan speed. Nothing here touches hardware or the
network; the fixture binds IPv4 loopback only.
"""

from __future__ import annotations

import threading
import time
from typing import Any

# Factory defaults observed from the original thorx1-1.0.6 firmware's
# GET /v2/miner/config under esp-emu (Normal 385 MHz / 98, Over 475 / 104).
DEFAULTS: dict[str, Any] = {
    "pool_url": "pool.invalid",
    "pool_worker": "hashfleet-virtual-miner",
    "pool_port": 3333,
    "pool_tls": 0,
    "pool_extranonce": 0,
    "fallback_pool_url": "backup.invalid",
    "fallback_pool_worker": "hashfleet-virtual-miner",
    "fallback_pool_port": 3333,
    "fallback_pool_tls": 0,
    "fallback_pool_extranonce": 0,
    "feature_tls_xnsub": False,
    "core_frequency": 385,
    "core_voltage": 98,
    "boot_mode": 0,
    "Normalfrequency": 385,
    "coreNormalVoltage": 98,
    "Overfrequency": 475,
    "coreOverVoltage": 104,
    "Customizefrequency": 385,
    "coreCustomizeVoltage": 98,
    "fan_mode": 0,
    "fan_target_speed": 80,
    "individual_freq": False,
    "timezone": "UTC",
    "ntpServer": "time.invalid",
    "ntpServerBackup": "time.invalid",
}

# PUT /v2/miner/config parameters from the reference (section 2.4), with types.
WRITABLE: dict[str, type | tuple[type, ...]] = {
    "pool_url": str, "pool_port": int, "worker_name": str, "worker_password": str,
    "core_voltage": (int, float), "core_frequency": (int, float), "boot_mode": int,
    "timezone": str, "ntpServer": str, "ntpServerBackup": str,
    "fan_mode": int, "fan_target_speed": int,
    "fallback_pool_url": str, "fallback_pool_worker": str, "fallback_pool_port": int,
    "fallback_pool_password": str,
}
# Safe synthetic bounds so a test client cannot produce absurd telemetry.
LIMITS = {"core_frequency": (100, 1000), "core_voltage": (60, 150), "fan_target_speed": (0, 100),
          "pool_port": (1, 65535), "fallback_pool_port": (1, 65535), "fan_mode": (0, 1), "boot_mode": (0, 3)}
SECRETS = {"worker_password", "fallback_pool_password"}
MAX_FAN_RPM = 6000
GHS_PER_MHZ_PER_CHIP = 4.2  # synthetic BM1373-class scale: 385 MHz -> about 1.6 TH/s per chip


class ThorDevice:
    """Thread-safe in-memory ThorOS state for one fixture instance."""

    def __init__(self, name: str, model: str, revision: str, asic: str, chips: int, degraded: bool):
        self._lock = threading.Lock()
        self.name, self.model, self.revision, self.asic = name, model, revision, asic
        self.chips = 0 if degraded else chips
        self.degraded = degraded
        self.config = dict(DEFAULTS)
        self.booted_at = time.monotonic()
        self.reboots = 0
        self.accepted = 0
        self.rejected = 0
        self.best = 0

    def _uptime(self) -> int:
        return int(time.monotonic() - self.booted_at)

    def info(self) -> dict[str, Any]:
        return {
            "device_model": self.model, "hardware_version": self.revision,
            "firmware_version": "api-fixture", "mac_address": "02:00:00:00:00:01",
            "serial_number": f"VIRTUAL-{self.model.replace(' ', '')}", "chip_type": self.asic,
            "compiled_time": "fixture", "runningPartition": "factory",
            "detected_chips_count": self.chips, "flipscreen": 1, "pagescroll": 1,
        }

    def status(self) -> dict[str, Any]:
        return {
            "uptime_seconds": self._uptime(), "free_heap_bytes": 250000, "cpu_temp": 45.0,
            "wifi_rssi": -50, "wifi_ssid": "HashFleet-Lab", "network_connected": True,
            "eth_link_up": False, "ethConnected": False, "ethStatus": "Link Down",
            "ip_address": "127.0.0.1", "ap_enabled": 0, "hostname": self.name,
        }

    def miner(self) -> dict[str, Any]:
        with self._lock:
            c = dict(self.config)
            uptime = self._uptime()
            freq = float(c["core_frequency"])
            volts = float(c["core_voltage"]) / 100.0
            ghs = 0.0 if self.degraded else GHS_PER_MHZ_PER_CHIP * freq * self.chips
            power = 0.0 if self.degraded else round(6.0 + self.chips * (freq / 385.0) * (volts / 0.98) ** 2 * 9.0, 1)
            fan_pct = c["fan_target_speed"] if c["fan_mode"] == 1 else min(100, max(30, int(power * 1.4)))
            rpm = int(MAX_FAN_RPM * fan_pct / 100)
            temp = 95.0 if self.degraded else round(30.0 + power * 0.9 - fan_pct * 0.18, 1)
            # Shares accrue slowly with uptime so dashboards see movement.
            if not self.degraded:
                self.accepted = uptime // 6
                self.rejected = uptime // 400
                self.best = max(self.best, 4096 * (1 + uptime // 30))
        return {
            "hostname": self.name,
            "current_hashrate": ghs * 1e9,
            "fan_speed_rpm": rpm, "fan_speed_rpm_1": max(0, rpm - 150),
            "temp_board": temp, "temp_board_1": round(temp - 2.0, 1), "temp_vcore": round(temp - 4.0, 1),
            "core_voltage_actual": round(volts, 3), "input_voltage": 12.0,
            "core_current_actual": round(power / max(volts, 0.1) / 12.0 * 3.0, 2) if power else 0.0,
            "power_consumption": power, "frequency": int(freq), "boot_mode": c["boot_mode"],
            "screen_bright": 100, "coreVoltage": c["core_voltage"],
            "Normalfrequency": c["Normalfrequency"], "coreNormalVoltage": c["coreNormalVoltage"],
            "Overfrequency": c["Overfrequency"], "coreOverVoltage": c["coreOverVoltage"],
            "Customizefrequency": c["Customizefrequency"], "coreCustomizeVoltage": c["coreCustomizeVoltage"],
            "pool_tls": c["pool_tls"], "pool_extranonce": c["pool_extranonce"],
            "fallback_pool_tls": c["fallback_pool_tls"], "fallback_pool_extranonce": c["fallback_pool_extranonce"],
            "feature_tls_xnsub": c["feature_tls_xnsub"],
            "power_efficiency": round(power / (ghs / 1000.0), 2) if ghs else 0.0,
            "fan_mode": c["fan_mode"], "fan_target_speed": c["fan_target_speed"],
            "shares_accepted": self.accepted, "shares_rejected": self.rejected,
            "nonce_mismatch_errors": 0, "queue_drop_errors": 0, "uart_crc_errors": 0,
            "stale_share_errors": 0, "duplicate_share_errors": 0, "low_diff_errors": 0,
            "domains_count": 1, "chips_per_domain": self.chips,
            "bestDiff": self.best, "bestSessionDiff": self.best,
            "displayFlash": False, "overheat_mode": 1 if self.degraded else 0, "stratumDiff": 1024,
            "isUsingFallbackStratum": False, "hwNumber": 0, "nonceNumber": self.accepted * 4, "hwRate": 0.0,
            "pool_url": c["pool_url"], "pool_worker": c["pool_worker"], "pool_port": c["pool_port"],
            "fallback_pool_url": c["fallback_pool_url"], "fallback_pool_worker": c["fallback_pool_worker"],
            "fallback_pool_port": c["fallback_pool_port"],
        }

    def miner_config(self) -> dict[str, Any]:
        with self._lock:
            c = dict(self.config)
        keys = [k for k in DEFAULTS if k not in ("timezone", "ntpServer", "ntpServerBackup")]
        out = {k: c[k] for k in keys}
        out["freq_0"] = c["core_frequency"]
        out["freq_1"] = 0
        return out

    def hashrate_history(self) -> dict[str, Any]:
        now = int(time.time())
        point = self.miner()
        return {"window_minutes": 1440, "interval_seconds": 900, "points": [
            {"timestamp": now - i * 900, "hashrate": point["current_hashrate"],
             "temp": point["temp_board"], "power": point["power_consumption"]} for i in range(4)]}

    def update(self, body: Any) -> tuple[int, dict[str, Any]]:
        """Apply a PUT /v2/miner/config body. Returns (status, envelope)."""
        if not isinstance(body, dict) or not body:
            return 400, {"ok": False, "message": "Expected a non-empty JSON object."}
        changes: dict[str, Any] = {}
        for key, value in body.items():
            expected = WRITABLE.get(key)
            if expected is None:
                return 400, {"ok": False, "message": f"Unknown field: {key}"}
            if isinstance(value, bool) or not isinstance(value, expected):
                return 400, {"ok": False, "message": f"Invalid type for {key}"}
            if key in LIMITS:
                low, high = LIMITS[key]
                if not low <= value <= high:
                    return 400, {"ok": False, "message": f"{key} out of range [{low}, {high}]"}
            if isinstance(value, str) and len(value) > 128:
                return 400, {"ok": False, "message": f"{key} too long"}
            changes[key] = value
        with self._lock:
            for key, value in changes.items():
                if key in SECRETS:
                    continue  # accepted, never stored or echoed
                target = {"worker_name": "pool_worker"}.get(key, key)
                if target in ("core_frequency", "core_voltage"):
                    value = int(round(value))
                if isinstance(value, str) and target.endswith("pool_url"):
                    for prefix in ("stratum+tcp://", "stratum+ssl://"):
                        if value.startswith(prefix):
                            value = value[len(prefix):]
                self.config[target] = value
            if "core_frequency" in changes or "core_voltage" in changes:
                self.config["Customizefrequency"] = self.config["core_frequency"]
                self.config["coreCustomizeVoltage"] = self.config["core_voltage"]
        return 200, {"ok": True, "message": "Configuration updated successfully."}

    def reboot(self) -> dict[str, Any]:
        with self._lock:
            self.booted_at = time.monotonic()
            self.reboots += 1
            self.accepted = self.rejected = 0
        return {"ok": True, "message": "Device is rebooting..."}
