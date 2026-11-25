"""Per-instance lifecycle. Stop only the process listening on its private Unix socket."""

from contextlib import ExitStack, contextmanager
from pathlib import Path
from tempfile import mkdtemp
import fcntl
import json
import os
import signal
import socket
import stat
import threading

from .backend import run_guest
from .config import LabError, Miner


CONTROL = "control.sock"


def private_directory(path: Path) -> Path:
    path.mkdir(mode=0o700, parents=True, exist_ok=True)
    details = path.lstat()
    if not stat.S_ISDIR(details.st_mode) or details.st_uid != os.getuid() or details.st_mode & 0o077:
        raise LabError(f"state directory must be a real, user-owned directory with mode 0700: {path}")
    return path


def control_path(directory: Path) -> Path:
    path = directory / CONTROL
    if len(os.fsencode(path)) > 100:
        raise LabError("the state directory is too long for a Unix socket; use a shorter --state-dir")
    return path


def instance_settings(miner: Miner) -> dict:
    return {
        "name": miner.name, "backend": miner.backend, "board": miner.board,
        "scenario": miner.scenario, "hardware": miner.hardware if miner.backend == "esp-emu" else None,
        "temperature_c": miner.temperature_c, "power_w": miner.power_w,
        "endpoint": f"http://127.0.0.1:{miner.http_port}",
    }


def control(directory: Path, action: str = "status") -> dict | None:
    path = control_path(directory)
    with socket.socket(socket.AF_UNIX) as connection:
        connection.settimeout(1)
        try:
            connection.connect(str(path))
        except (FileNotFoundError, ConnectionRefusedError):
            return None
        try:
            connection.sendall(action.encode("ascii") + b"\n")
            with connection.makefile("rb") as stream:
                return json.loads(stream.readline(8192))
        except (ValueError, OSError) as error:
            raise LabError(f"instance control socket did not answer: {directory.name}") from error


@contextmanager
def _owned_socket(directory: Path):
    path = control_path(directory)
    with (directory / "control.lock").open("ab") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise LabError(f"instance already running or starting: {directory.name}") from error
        if path.is_socket():
            path.unlink()
        with socket.socket(socket.AF_UNIX) as listener:
            listener.bind(str(path))
            try:
                listener.listen(8)
                listener.settimeout(0.25)
                yield listener
            finally:
                path.unlink(missing_ok=True)


def supervise(miner: Miner, state: Path, cache: Path) -> None:
    from .api_fixture import make_fixture
    from .http_gateway import make_gateway

    directory = private_directory(state / miner.name)
    stopping = threading.Event()
    previous = {
        signum: signal.signal(signum, lambda _signum, _frame: stopping.set())
        for signum in (signal.SIGTERM, signal.SIGINT)
    }
    try:
        with ExitStack() as stack:
            # The lock also covers startup, but no control request is processed until ready.
            listener = stack.enter_context(_owned_socket(directory))
            guest = None
            if miner.backend == "esp-emu":
                run = Path(mkdtemp(prefix="run-", dir=directory))
                guest = stack.enter_context(run_guest(miner, cache, run))
                server = make_gateway(miner.http_port, guest.guest_port)
            else:
                run = None
                server = make_fixture(miner)
            stack.callback(server.server_close)
            thread = threading.Thread(target=server.serve_forever, kwargs={"poll_interval": 0.1}, daemon=True)
            thread.start()
            stack.callback(thread.join)
            stack.callback(server.shutdown)

            status = {
                **instance_settings(miner), "running": True, "run": str(run) if run else None,
            }
            print(json.dumps(status), flush=True)
            while not stopping.is_set():
                if guest:
                    guest.assert_healthy()
                try:
                    connection, _ = listener.accept()
                except TimeoutError:
                    continue
                with connection:
                    connection.settimeout(0.3)
                    try:
                        with connection.makefile("rb") as request:
                            action = request.readline(32)
                            if action == b"stop\n":
                                stopping.set()
                            reply = status if action in (b"status\n", b"stop\n") else {"error": "unknown action"}
                            connection.sendall(json.dumps(reply).encode() + b"\n")
                    except OSError:
                        continue
    finally:
        for signum, handler in previous.items():
            signal.signal(signum, handler)
