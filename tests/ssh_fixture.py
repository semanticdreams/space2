#!/usr/bin/env python3
"""Disposable OpenSSH fixture for Space SSH integration tests."""

from __future__ import annotations

import argparse
import os
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path


def find_tool(name: str) -> str | None:
    return shutil.which(name)


def env_enabled(name: str) -> bool:
    return os.environ.get(name) == "1"


def allocate_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return int(sock.getsockname()[1])


class EchoServer:
    def __init__(self) -> None:
        self._sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self._sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self._sock.bind(("127.0.0.1", 0))
        self.host = "127.0.0.1"
        self.port = int(self._sock.getsockname()[1])
        self._stop = threading.Event()
        self._thread = threading.Thread(target=self._run, name="space-ssh-echo-fixture", daemon=True)

    def start(self) -> None:
        self._sock.listen(16)
        self._thread.start()

    def close(self) -> None:
        self._stop.set()
        try:
            with socket.create_connection((self.host, self.port), timeout=0.2):
                pass
        except OSError:
            pass
        self._thread.join(timeout=2.0)
        self._sock.close()

    def _run(self) -> None:
        while not self._stop.is_set():
            try:
                conn, _addr = self._sock.accept()
            except OSError:
                return
            with conn:
                while True:
                    data = conn.recv(4096)
                    if not data:
                        break
                    conn.sendall(data)


def run_checked(args: list[str], *, stdout: int | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(args, check=True, text=True, stdout=stdout, stderr=subprocess.PIPE)


def write_sshd_config(path: Path, *, port: int, host_key: Path, authorized_keys: Path, sftp_root: Path) -> None:
    path.write_text(
        "\n".join(
            [
                f"Port {port}",
                "ListenAddress 127.0.0.1",
                "AddressFamily inet",
                f"HostKey {host_key}",
                f"AuthorizedKeysFile {authorized_keys}",
                "PasswordAuthentication no",
                "KbdInteractiveAuthentication no",
                "ChallengeResponseAuthentication no",
                "PubkeyAuthentication yes",
                "AcceptEnv SPACE_SSH_ENV_PROBE",
                "PermitRootLogin yes",
                "UsePAM no",
                "StrictModes no",
                "LogLevel ERROR",
                f"PidFile {sftp_root / 'sshd.pid'}",
                "Subsystem sftp internal-sftp",
                "AllowTcpForwarding yes",
                "PermitOpen any",
                "PermitListen any",
                "X11Forwarding no",
                "PermitTTY yes",
                "",
            ]
        ),
        encoding="utf-8",
    )


def wait_for_port(port: int, process: subprocess.Popen[str]) -> bool:
    deadline = time.monotonic() + 10.0
    while time.monotonic() < deadline:
        if process.poll() is not None:
            return False
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.2):
                return True
        except OSError:
            time.sleep(0.05)
    return False


def stop_process(process: subprocess.Popen[str]) -> None:
    if process.poll() is not None:
        return
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    try:
        process.wait(timeout=5.0)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.wait(timeout=5.0)


def stop_and_collect_start_failure(process: subprocess.Popen[str]) -> tuple[int | None, str]:
    if process.poll() is None:
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    try:
        _stdout, stderr = process.communicate(timeout=5.0)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        _stdout, stderr = process.communicate(timeout=5.0)
    return process.returncode, (stderr or "")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--space", required=True, help="Space executable to run")
    parser.add_argument("--assets", required=True, help="Space assets directory")
    parser.add_argument("--module", required=True, help="Fennel module entry point")
    return parser.parse_args()


class FixtureStrictModeTests(unittest.TestCase):
    def run_fixture_without_tools(self, *, require_fixture: bool) -> subprocess.CompletedProcess[str]:
        env = os.environ.copy()
        env["PATH"] = "/tmp/space/tests/missing-openssh-tools"
        if require_fixture:
            env["SPACE_TEST_REQUIRE_SSH_FIXTURE"] = "1"
        else:
            env.pop("SPACE_TEST_REQUIRE_SSH_FIXTURE", None)
        return subprocess.run(
            [sys.executable, __file__, "--space", "unused", "--assets", ".", "--module", "unused"],
            check=False,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )

    def test_missing_fixture_tools_skip_by_default(self) -> None:
        result = self.run_fixture_without_tools(require_fixture=False)

        self.assertEqual(result.returncode, 0)
        self.assertIn("SKIP space_ssh_integration:", result.stdout)

    def test_missing_fixture_tools_fail_when_required(self) -> None:
        result = self.run_fixture_without_tools(require_fixture=True)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("ERROR space_ssh_integration: missing required fixture tool:", result.stderr)
        self.assertIn("sshd", result.stderr)
        self.assertIn("ssh-keygen", result.stderr)
        self.assertIn("ssh-keyscan", result.stderr)


def main() -> int:
    args = parse_args()
    sshd = find_tool("sshd")
    ssh_keygen = find_tool("ssh-keygen")
    ssh_keyscan = find_tool("ssh-keyscan")
    missing = [name for name, value in [("sshd", sshd), ("ssh-keygen", ssh_keygen), ("ssh-keyscan", ssh_keyscan)] if not value]
    if missing:
        if env_enabled("SPACE_TEST_REQUIRE_SSH_FIXTURE"):
            print(
                f"ERROR space_ssh_integration: missing required fixture tool: {', '.join(missing)}",
                file=sys.stderr,
            )
            return 1
        print(f"SKIP space_ssh_integration: missing OpenSSH fixture dependencies: {', '.join(missing)}")
        return 0

    sshd_path = Path(sshd).resolve()
    if not sshd_path.is_absolute():
        print("ERROR space_ssh_integration: sshd path is not absolute", file=sys.stderr)
        return 1

    fixture_parent = Path("/tmp/space/tests")
    fixture_parent.mkdir(parents=True, exist_ok=True)
    root = Path(tempfile.mkdtemp(prefix="ssh-fixture-", dir=str(fixture_parent)))
    sshd_process: subprocess.Popen[str] | None = None
    echo_server: EchoServer | None = None
    previous_sigterm = signal.getsignal(signal.SIGTERM)

    def handle_sigterm(signum: int, _frame: object) -> None:
        if sshd_process is not None:
            stop_process(sshd_process)
        if echo_server is not None:
            echo_server.close()
        shutil.rmtree(root, ignore_errors=True)
        if callable(previous_sigterm):
            previous_sigterm(signum, _frame)
        raise SystemExit(128 + signum)

    signal.signal(signal.SIGTERM, handle_sigterm)

    try:
        key_path = root / "client_key"
        host_key = root / "host_key"
        authorized_keys = root / "authorized_keys"
        known_hosts = root / "known_hosts"
        sftp_root = root / "sftp-root"
        config_path = root / "sshd_config"
        sftp_root.mkdir(mode=0o700)
        known_hosts.write_text("", encoding="utf-8")

        run_checked([ssh_keygen, "-q", "-t", "ed25519", "-N", "", "-f", str(key_path)], stdout=subprocess.DEVNULL)
        run_checked([ssh_keygen, "-q", "-t", "ed25519", "-N", "", "-f", str(host_key)], stdout=subprocess.DEVNULL)
        public_key = (key_path.with_suffix(".pub") if key_path.suffix else Path(str(key_path) + ".pub")).read_text(encoding="utf-8")
        authorized_keys.write_text(public_key, encoding="utf-8")
        key_path.chmod(0o600)
        authorized_keys.chmod(0o600)

        ssh_port = allocate_port()
        local_tunnel_port = allocate_port()
        remote_tunnel_port = allocate_port()
        echo_server = EchoServer()
        echo_server.start()
        write_sshd_config(config_path, port=ssh_port, host_key=host_key, authorized_keys=authorized_keys, sftp_root=sftp_root)

        sshd_process = subprocess.Popen(
            [str(sshd_path), "-D", "-e", "-f", str(config_path)],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            start_new_session=True,
        )
        if not wait_for_port(ssh_port, sshd_process):
            returncode, stderr = stop_and_collect_start_failure(sshd_process)
            detail = stderr.strip() or f"sshd return code {returncode}"
            print(f"ERROR space_ssh_integration: disposable sshd did not start: {detail}", file=sys.stderr)
            return 1

        env = os.environ.copy()
        assets = str(Path(args.assets).resolve())
        env.update(
            {
                "SKIP_KEYRING_TESTS": "1",
                "XDG_DATA_HOME": "/tmp/space/tests/xdg-data",
                "SPACE_DISABLE_AUDIO": "1",
                "SPACE_LOG_DIR": "/tmp/space/tests/log",
                "SPACE_ASSETS_PATH": assets,
                "FENNEL_PATH": f"{assets}/lua/?.fnl;{assets}/lua/?/init.fnl",
                "FENNEL_MACRO_PATH": f"{assets}/lua/?.fnl;{assets}/lua/?/init.fnl",
                "SPACE_TEST_SSH_HOST": "127.0.0.1",
                "SPACE_TEST_SSH_PORT": str(ssh_port),
                "SPACE_TEST_SSH_USER": os.environ.get("USER") or os.environ.get("LOGNAME") or "ubuntu",
                "SPACE_TEST_SSH_KEY": str(key_path),
                "SPACE_TEST_SSH_KNOWN_HOSTS": str(known_hosts),
                "SPACE_TEST_SSH_ROOT": str(sftp_root),
                "SPACE_TEST_SSH_ECHO_HOST": echo_server.host,
                "SPACE_TEST_SSH_ECHO_PORT": str(echo_server.port),
                "SPACE_TEST_SSH_LOCAL_TUNNEL_PORT": str(local_tunnel_port),
                "SPACE_TEST_SSH_REMOTE_TUNNEL_PORT": str(remote_tunnel_port),
            }
        )
        command = [args.space, "-m", args.module]
        completed = subprocess.run(command, env=env, cwd=str(Path(args.assets).resolve().parent))
        return int(completed.returncode)
    finally:
        signal.signal(signal.SIGTERM, previous_sigterm)
        if sshd_process is not None:
            stop_process(sshd_process)
        if echo_server is not None:
            echo_server.close()
        shutil.rmtree(root, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
