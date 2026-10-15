#!/usr/bin/env python3
"""Fixture-only CLI entry: transfer ownership of each actual app spawn by pidfd.

The production CLI/settings are unchanged. Intent is persisted before Popen;
the known, unreaped direct child's kernel identity and held fd are sent to the
fixture before the CLI starts waiting for runtime registry publication.
No recipe arguments or environment are serialized.
"""
import array
import importlib.util
import json
import os
from pathlib import Path
import signal
import socket
import sys
import uuid


def capture_child(module, child, checkout, executable, launch_id):
    fd = os.pidfd_open(child.pid)
    try:
        proc = Path("/proc") / str(child.pid)
        record = {"instance-id": "spawn-" + launch_id, "checkout-root": str(checkout),
                  "pid": child.pid, "uid": proc.stat().st_uid,
                  "boot-id": Path("/proc/sys/kernel/random/boot_id").read_text().strip(),
                  "process-start": (proc / "stat").read_text().rsplit(")", 1)[1].split()[19],
                  "executable": str(Path(executable).resolve(strict=True)),
                  "executable-identity": module._executable_identity(Path(executable))}
        module._check_process(record)
        return record, fd
    except BaseException:
        os.close(fd)
        raise


def observe_launch(module, launch, observer_root, checkout, recipe):
    launch_id = uuid.uuid4().hex
    intent = {"launch-id": launch_id, "checkout-root": str(checkout), "state": "pending"}
    path = Path(observer_root) / "launches" / (launch_id + ".json")
    module._write_json(path, intent)
    try:
        child = launch(checkout, recipe)
    except module.LiveDevError as error:
        if error.code == "launch-failed":
            module._write_json(path, dict(intent, state="no-child"))
        raise
    fd = None
    record = None
    try:
        record, fd = capture_child(module, child, checkout, recipe["executable"], launch_id)
        intent = dict(intent, record=record)
        module._write_json(path, dict(intent, state="captured"))
        payload = json.dumps({"launch-id": launch_id, "record": record}).encode()
        with socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM) as sender:
            sender.connect(str(Path(observer_root) / "spawns.sock"))
            sent = sender.sendmsg([payload], [(socket.SOL_SOCKET, socket.SCM_RIGHTS, array.array("i", [fd]))])
            if sent != len(payload):
                raise RuntimeError("incomplete fixture spawn transfer")
        module._write_json(path, dict(intent, state="reported"))
    except BaseException:
        # If transfer fails, never lose a still-owned, unchanged-image child
        # silently. Otherwise leave pending provenance and fail cleanup loudly.
        if fd is not None and record is not None:
            module._check_process(record)
            signal.pidfd_send_signal(fd, signal.SIGTERM)
            module._await_exit(record, fd, 5)
            child.wait(timeout=5)
            module._write_json(path, dict(intent, state="exited"))
        elif child.poll() is not None:
            module._write_json(path, dict(intent, state="exited"))
        raise
    finally:
        if fd is not None:
            os.close(fd)
    return child


def main():
    path = Path(__file__).parents[1] / "scripts/live_dev.py"
    spec = importlib.util.spec_from_file_location("live_dev", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    observer_root = Path(os.environ["SPACE_LIVE_DEV_OBSERVER_ROOT"])
    original = module._launch
    def launch(root, recipe):
        return observe_launch(module, original, observer_root, root, recipe)
    module._launch = launch
    return module.main(sys.argv[1:])


if __name__ == "__main__":
    raise SystemExit(main())
