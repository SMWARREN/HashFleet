"""Pin official artifacts by digest. Setup is the only command that downloads."""

from dataclasses import dataclass
from hashlib import file_digest
from pathlib import Path, PurePosixPath
import os
import platform
import shutil
import tarfile
import tempfile
import urllib.error
import urllib.parse
import urllib.request

from .config import (
    Board, FIRMWARE_TAG, LabError, THOROS_BOOT_FILE, THOROS_BOOT_REPO, THOROS_BOOT_SHA256, THOROS_BOOT_TAG,
)


@dataclass(frozen=True)
class Asset:
    repo: str
    tag: str
    file: str
    sha256: str

    @property
    def url(self) -> str:
        return f"https://github.com/{self.repo}/releases/download/{self.tag}/{self.file}"


EMULATOR_TAG = "v1.2.0"
EMULATORS = {
    ("Darwin", "arm64"): ("aarch64-apple-darwin", "2406dbec04bcb8ee207e512cbb98a8c5478c9dad94ee18f1b3b14c384ab5eb6f"),
    ("Linux", "aarch64"): ("aarch64-unknown-linux-gnu", "5481a2840c6b521d57709d1f7cad03fbcfe9dbedafda28d7d2635d2cbbedabd5"),
    ("Linux", "x86_64"): ("x86_64-unknown-linux-gnu", "560236344fd69dc8d74bc862c79aea01f7a69ac626ae3f54b1b0946bbce078c1"),
}
MAX_DOWNLOAD = 32 * 1024 * 1024


def emulator_asset() -> Asset:
    try:
        platform_tag, digest = EMULATORS[(platform.system(), platform.machine())]
    except KeyError as error:
        raise LabError("no pinned esp-emu for this host (supported: Apple Silicon or Linux x86_64/aarch64)") from error
    return Asset("espressif/esp-emulator", EMULATOR_TAG, f"esp-emu-{EMULATOR_TAG[1:]}-{platform_tag}.tar.gz", digest)


def firmware_asset(board: Board) -> Asset:
    return Asset(board.repo, board.tag or FIRMWARE_TAG, board.flash_asset, board.flash_sha256)


def thoros_boot_asset() -> Asset:
    return Asset(THOROS_BOOT_REPO, THOROS_BOOT_TAG, THOROS_BOOT_FILE, THOROS_BOOT_SHA256)


def board_assets(board: Board) -> tuple[Asset, ...]:
    return (firmware_asset(board), thoros_boot_asset()) if board.api == "thoros" else (firmware_asset(board),)


def sha256(path: Path) -> str:
    with path.open("rb") as stream:
        return file_digest(stream, "sha256").hexdigest()


class _ReleaseRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        parsed = urllib.parse.urlsplit(newurl)
        if parsed.scheme != "https" or parsed.hostname not in (
            "github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com",
        ):
            raise LabError("release download attempted an unexpected redirect")
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def install_asset(cache: Path, asset: Asset) -> Path:
    cache.mkdir(mode=0o700, parents=True, exist_ok=True)
    path = cache / asset.file
    if path.exists():
        if sha256(path) != asset.sha256:
            raise LabError(f"digest mismatch: {path}. Move it aside before running setup again")
        return path
    opener = urllib.request.build_opener(_ReleaseRedirect())
    try:
        with tempfile.NamedTemporaryFile(dir=cache) as partial:
            request = urllib.request.Request(asset.url, headers={"User-Agent": "HashFleet-Virtual-Miner-Lab"})
            with opener.open(request, timeout=20) as response:
                remaining = MAX_DOWNLOAD
                while block := response.read(64 * 1024):
                    remaining -= len(block)
                    if remaining < 0:
                        raise LabError(f"release download exceeds limit: {asset.file}")
                    partial.write(block)
            partial.flush()
            if sha256(Path(partial.name)) != asset.sha256:
                raise LabError(f"download digest mismatch: {asset.file}")
            # Link atomically while the named temporary is still owned by its context.
            try:
                os.link(partial.name, path)
            except FileExistsError:
                if sha256(path) != asset.sha256:
                    raise LabError(f"digest mismatch: {path}") from None
    except (OSError, urllib.error.URLError) as error:
        raise LabError(f"unable to download {asset.file}: {error}") from error
    return path


def extract_runner(archive: Path, destination: Path) -> Path:
    """Never extract archive paths. Copy only the pinned, regular executable."""
    try:
        with tarfile.open(archive, "r:gz") as tar:
            matches = [member for member in tar if PurePosixPath(member.name).name == "esp-emu"]
            if len(matches) != 1 or not matches[0].isfile() or not 1 <= matches[0].size <= 64 * 1024 * 1024:
                raise LabError("pinned native archive did not contain one regular esp-emu executable")
            source = tar.extractfile(matches[0])
            if source is None:
                raise LabError("cannot read esp-emu executable from the archive")
            with source, tempfile.NamedTemporaryFile(dir=destination, delete=False) as partial:
                temp = Path(partial.name)
                try:
                    shutil.copyfileobj(source, partial)
                    partial.flush()
                    os.fchmod(partial.fileno(), 0o700)
                    path = destination / "esp-emu"
                    os.replace(temp, path)
                finally:
                    temp.unlink(missing_ok=True)
    except (tarfile.TarError, OSError) as error:
        raise LabError(f"cannot unpack native emulator: {error}") from error
    return path


def prepare_offline(cache: Path, board: Board, destination: Path) -> tuple[Path, Path, Path | None]:
    emulator = emulator_asset()
    for asset in (emulator, *board_assets(board)):
        path = cache / asset.file
        if not path.is_file():
            raise LabError(f"missing {asset.file}. Run 'setup' to download pinned artifacts")
        if sha256(path) != asset.sha256:
            raise LabError(f"refusing to run: digest mismatch for {asset.file}")
    boot = cache / THOROS_BOOT_FILE if board.api == "thoros" else None
    return extract_runner(cache / emulator.file, destination), cache / board.flash_asset, boot
