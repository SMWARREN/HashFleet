"""Native firmware runner. The public port is served by the GET-only gateway."""

from contextlib import ExitStack, contextmanager
from pathlib import Path
from queue import Empty, SimpleQueue
import platform
import socket
import subprocess
import threading
import time
from typing import Callable

from .assets import EMULATOR_TAG, prepare_offline
from .config import FIRMWARE_TAG, LabError, Miner
from .provision import PASSWORD, SSID, provision


MAC_SANDBOX = """(version 1)
(allow default)
(deny network*)
"""
LOG_LIMIT = 24 * 1024 * 1024


def isolated_command(argv: list[str], *, listener_ports: tuple[int, ...] = ()) -> list[str]:
    if platform.system() == "Darwin":
        sandbox = Path("/usr/bin/sandbox-exec")
        if sandbox.is_file():
            if any(type(port) is not int or not 1 <= port <= 65535 for port in listener_ports):
                raise LabError("invalid sandbox listener port")
            # SBPL's localhost predicate does not enforce the bind address. The
            # pinned emulator is explicitly configured to bind to 127.0.0.1.
            profile = MAC_SANDBOX + "".join(
                f'(allow network-bind network-inbound (local tcp "localhost:{port}"))\n'
                for port in listener_ports
            )
            return [str(sandbox), "-p", profile, *argv]
        raise LabError("macOS sandbox-exec is required; refusing an unsandboxed firmware run")
    if platform.system() == "Linux":
        try:
            interfaces = {entry.name for entry in Path("/sys/class/net").iterdir()}
        except OSError as error:
            raise LabError("cannot verify an isolated Linux network namespace") from error
        if interfaces == {"lo"}:
            return argv
        raise LabError("use a Linux container with --network none (loopback only); refusing a host-network firmware run")
    raise LabError("no verified network isolation strategy for this host OS")


def _ports(count: int, excluded: int) -> list[int]:
    with ExitStack() as hold:
        ports = []
        while len(ports) < count:
            listener = hold.enter_context(socket.socket(socket.AF_INET, socket.SOCK_STREAM))
            listener.bind(("127.0.0.1", 0))
            number = listener.getsockname()[1]
            if number != excluded:
                ports.append(number)
        return ports


def _wait_for_loopback_forward(child: subprocess.Popen, log: Path, port: int) -> None:
    marker = f"user-net: hostfwd TCP 127.0.0.1:{port} -> guest:80".encode()
    deadline = time.monotonic() + 8
    while time.monotonic() < deadline and child.poll() is None:
        with log.open("rb") as stream:
            if marker in stream.read(128 * 1024):
                return
        time.sleep(0.025)
    raise LabError(f"emulator did not establish its loopback forward; see {log}")


def _verify_native_listeners(child: subprocess.Popen, ports: tuple[int, ...]) -> None:
    if platform.system() != "Darwin":
        return  # Linux requires a loopback-only network namespace before launch.
    try:
        result = subprocess.run(
            ["/usr/sbin/lsof", "-nP", "-a", "-p", str(child.pid), "-iTCP", "-sTCP:LISTEN", "-Fn"],
            capture_output=True, text=True, timeout=4,
        )
    except subprocess.TimeoutExpired as error:
        raise LabError("timed out verifying emulator listener addresses") from error
    observed = {line[1:] for line in result.stdout.splitlines() if line.startswith("n")}
    if result.returncode != 0 or observed != {f"127.0.0.1:{port}" for port in ports}:
        raise LabError("emulator TCP listener addresses did not match the assigned IPv4 loopback ports")


class Guest:
    def __init__(self, child: subprocess.Popen, guest_port: int, directory: Path):
        self.child = child
        self.guest_port = guest_port
        self.directory = directory
        self.failures: SimpleQueue[Exception] = SimpleQueue()

    def assert_healthy(self) -> None:
        try:
            self.failures.get_nowait()
        except Empty:
            pass
        else:
            raise LabError(f"board co-simulation stopped; see {self.directory / 'serial.log'}")
        if (code := self.child.poll()) is not None:
            raise LabError(f"emulator exited ({code}); see {self.directory / 'serial.log'}")
        path = self.directory / "serial.log"
        if path.stat().st_size > LOG_LIMIT:
            raise LabError(f"emulator log limit reached: {path}")


@contextmanager
def run_guest(miner: Miner, assets: Path, directory: Path):
    runner, original, boot = prepare_offline(assets, miner.profile, directory)
    image = directory / "flash.bin"
    thoros = miner.profile.api == "thoros"
    if thoros:
        from .thoros_flash import compose

        digest = compose(boot, original, image)
    else:
        digest = provision(original, image, miner)
    # Simulated boards have distinct hostname/ports and independent Wi-Fi, flash and state.
    guest_port, *board_ports = _ports(3 if miner.hardware == "board" else 1, miner.http_port)
    listener_ports = (guest_port, *board_ports)
    net = f"user,restrict=yes,dns=127.0.0.1,net=10.0.2.0/24,hostfwd=tcp:127.0.0.1:{guest_port}-:80"
    argv = [
        str(runner), "--chip", "esp32s3", "--firmware", str(image),
        *(() if thoros else ("--wifi-ssid", SSID, "--wifi-password", PASSWORD)),
        "--net", net, "--log-color", "never",
    ]
    if board_ports:
        cosim_port, uart_port = board_ports
        board = directory / "board.json"
        board.write_text('{"parts": {}}\n', encoding="ascii")
        argv += [
            "--cosim-board", str(board),
            "--cosim-tcp", f"127.0.0.1:{cosim_port}",
            "--uart1-tcp", f"127.0.0.1:{uart_port}",
        ]
    log = directory / "serial.log"
    stop = threading.Event()
    sidecars: list[threading.Thread] = []
    with log.open("xb") as serial:
        firmware = miner.profile.flash_asset if thoros else f"ESP-Miner {FIRMWARE_TAG}"
        serial.write(f"# {firmware}; native esp-emu {EMULATOR_TAG}\n".encode())
        serial.write(f"# {'vendor app' if thoros else 'factory'} sha256 {miner.profile.flash_sha256}\n".encode())
        overlay = "composed bootloader/table/NVS" if thoros else "local NVS-only overlay"
        serial.write(f"# {overlay} flash sha256 {digest}\n".encode())
        serial.flush()
        child = subprocess.Popen(
            isolated_command(argv, listener_ports=listener_ports),
            cwd=directory, stdin=subprocess.DEVNULL,
            stdout=serial, stderr=subprocess.STDOUT,
            env={
                "HOME": str(directory), "PATH": "/usr/bin:/bin", "LANG": "C", "TZ": "UTC",
                "RUST_LOG": "info", "ESP_EMU_DISABLE_AUTOUPDATES": "1",
            },
        )
        guest = Guest(child, guest_port, directory)
        try:
            if board_ports:
                from .cosim import attach, attach_uart1

                def peripheral(kind: str, service: Callable, port: int) -> None:
                    try:
                        deadline = time.monotonic() + 3
                        while not stop.is_set():
                            try:
                                service(port, miner, stop)
                                break
                            except ConnectionRefusedError:
                                if time.monotonic() >= deadline or child.poll() is not None:
                                    raise
                                stop.wait(0.01)
                        if not stop.is_set():
                            guest.failures.put(LabError(f"unexpected end of {kind} sidecar"))
                    except Exception as error:
                        if not stop.is_set():
                            serial.write(f"\n# {kind} sidecar error: {type(error).__name__}\n".encode())
                            serial.flush()
                            guest.failures.put(error)

                for kind, service, port in (("I2C", attach, cosim_port), ("UART1", attach_uart1, uart_port)):
                    sidecar = threading.Thread(target=peripheral, args=(kind, service, port), daemon=True)
                    sidecars.append(sidecar)
                    sidecar.start()
            _wait_for_loopback_forward(child, log, guest_port)
            _verify_native_listeners(child, listener_ports)
            guest.assert_healthy()
            yield guest
        finally:
            stop.set()
            if child.poll() is None:
                child.terminate()
                try:
                    child.wait(timeout=4)
                except subprocess.TimeoutExpired:
                    child.kill()
                    child.wait()
            for sidecar in sidecars:
                sidecar.join(timeout=2)
