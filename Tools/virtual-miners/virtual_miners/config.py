"""Strict local lab configuration. Network destinations are not configurable."""

from dataclasses import dataclass
from math import isfinite
from pathlib import Path
import re
import tomllib


class LabError(Exception):
    """A configuration or runtime error safe to print at the CLI."""


@dataclass(frozen=True)
class Board:
    revision: str
    asic: str
    count: int
    flash_asset: str
    flash_sha256: str


BOARDS = {
    "gamma-601": Board(
        "601", "BM1370", 1,
        "esp-miner-factory-601-v2.15.4.bin",
        "d6307ce762d3fad529b705ad9c3b8fae96b66bd35125585b006f132c9de10184",
    ),
}
FIRMWARE_TAG = "v2.15.4"
NAME = re.compile(r"[a-z][a-z0-9-]{0,23}\Z")
REAL_SCENARIOS = {"normal", "overheat", "asic-missing", "no-power", "offline"}
FIXTURE_SCENARIOS = {"normal", "degraded"}


@dataclass(frozen=True)
class Miner:
    name: str
    board: str
    backend: str
    http_port: int
    scenario: str = "normal"
    temperature_c: float = 48.0
    power_w: float = 14.0
    hardware: str = "board"

    @property
    def profile(self) -> Board:
        return BOARDS[self.board]


def load(path: Path) -> dict[str, Miner]:
    try:
        with path.open("rb") as stream:
            config = tomllib.load(stream)
    except (OSError, UnicodeError, ValueError) as error:
        raise LabError(f"cannot read lab configuration: {error}") from error
    entries = config.get("miner")
    if set(config) != {"miner"} or not isinstance(entries, list) or not 1 <= len(entries) <= 16:
        raise LabError("configuration requires 1 to 16 [[miner]] entries, with no other sections")
    miners: dict[str, Miner] = {}
    ports: set[int] = set()
    for entry in entries:
        try:
            miner = Miner(**entry)
        except TypeError as error:
            raise LabError(f"invalid [[miner]] fields: {error}") from error
        if not isinstance(miner.name, str) or not NAME.fullmatch(miner.name):
            raise LabError("miner names must match [a-z][a-z0-9-]{0,23}")
        if miner.name in miners:
            raise LabError(f"duplicate miner name: {miner.name}")
        if not isinstance(miner.board, str) or miner.board not in BOARDS:
            raise LabError(f"{miner.name}: unsupported board")
        if miner.backend not in ("esp-emu", "api-fixture"):
            raise LabError(f"{miner.name}: backend must be esp-emu or api-fixture")
        if type(miner.http_port) is not int or not 1024 <= miner.http_port <= 65535:
            raise LabError(f"{miner.name}: http_port must be a non-privileged TCP port")
        if miner.http_port in ports:
            raise LabError(f"duplicate http_port: {miner.http_port}")
        scenarios = REAL_SCENARIOS if miner.backend == "esp-emu" else FIXTURE_SCENARIOS
        if not isinstance(miner.scenario, str) or miner.scenario not in scenarios:
            raise LabError(f"{miner.name}: unknown scenario")
        if miner.hardware not in ("board", "bare"):
            raise LabError(f"{miner.name}: hardware must be board or bare")
        if miner.backend == "esp-emu" and miner.hardware == "bare" and miner.scenario != "normal":
            raise LabError(f"{miner.name}: bare firmware does not support board fault scenarios")
        for key, value, low, high in (
            ("temperature_c", miner.temperature_c, 0, 110), ("power_w", miner.power_w, 0, 40),
        ):
            if type(value) not in (int, float) or not low <= value <= high or not isfinite(value):
                raise LabError(f"{miner.name}: {key} must be a finite number in [{low}, {high}]")
        miners[miner.name] = miner
        ports.add(miner.http_port)
    return miners
