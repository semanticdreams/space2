#!/usr/bin/env python3
"""Real normal-main lifecycle acceptance test; Linux/xvfb, never a user app.

Only Lua assets are copied into a temporary Git checkout. Non-code assets fall
back to the supplied repo. Reporting is disabled *before* copied main startup.
"""
import argparse
import array
import importlib.util
import json
import os
from pathlib import Path
import resource
import select
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time


def load_cli(repo):
    spec = importlib.util.spec_from_file_location("live_dev", repo / "scripts/live_dev.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_observer(repo):
    spec = importlib.util.spec_from_file_location("live_dev_spawn_observer", repo / "tests/live_dev_spawn_observer.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class Fixture:
    def __init__(self, directory, repo, space):
        self.base = Path(directory)
        self.repo = repo
        self.root = self.base / "checkout"
        self.root.mkdir()
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)
        self.lua = self.root / "assets/lua"
        shutil.copytree(repo / "assets/lua", self.lua)
        self.build = self.root / "build"
        self.build.mkdir()
        (self.build / "space").symlink_to(space)
        self.original_main = (self.lua / "main.fnl").read_text()
        self.narrow_reload_unit_ids = []
        self.module = load_cli(repo)
        self.instances = {}
        self.children = []
        self.launchers = []
        self.env = dict(os.environ)
        # Do not inherit a user's data, config, registry, dotenv, or log roots.
        for name in ("data", "config", "cache", "state", "runtime", "logs", "home", "config-dirs", "data-dirs"):
            (self.base / name).mkdir(mode=0o700)
        self.env.update(HOME=str(self.base / "home"), XDG_DATA_HOME=str(self.base / "data"),
                        XDG_CONFIG_HOME=str(self.base / "config"), XDG_CACHE_HOME=str(self.base / "cache"),
                        XDG_STATE_HOME=str(self.base / "state"), XDG_RUNTIME_DIR=str(self.base / "runtime"),
                        XDG_CONFIG_DIRS=str(self.base / "config-dirs"), XDG_DATA_DIRS=str(self.base / "data-dirs"),
                        SPACE_LOG_DIR=str(self.base / "logs"), SPACE_DISABLE_AUDIO="1", SKIP_KEYRING_TESTS="1",
                        SPACE_HOT_RELOAD="1", SPACE_HOT_RELOAD_WATCH_PATH=str(self.lua),
                        SPACE_FENNEL_BYTECODE="0", SDL_VIDEODRIVER="x11", SPACE_SKIP_CEF="1",
                        LIVE_DEV_SENTINEL_SECRET="fixture-private-λ")
        paths = f"{self.lua}/?.fnl;{self.lua}/?/init.fnl"
        self.env.update(SPACE_ASSETS_PATH=f"{self.lua.parent}{os.pathsep}{repo / 'assets'}",
                        FENNEL_PATH=paths, FENNEL_MACRO_PATH=paths)
        self.setup_spawn_observer()
        # No fallback into /tmp's user registry: keep native socket base short.
        assert len(str(self.base / "runtime/space-live-dev").encode()) < 70
        self.write_marker("v1")

    def write_marker(self, marker):
        first = "(global app (or app {}))"
        assert self.original_main.startswith(first)
        prefix = (first + "\n(require :tests.live-dev-offline)\n"
                  f'(set app.hot-reload-config {{:enabled true :narrow-reload-unit-ids [{" ".join(json.dumps(unit) for unit in self.narrow_reload_unit_ids)}]}})\n'
                  f"(set app.live-dev-fixture-marker {json.dumps(marker)})\n"
                  '(when app.__live-dev-fixture-fault? (error "fixture load failure"))\n')
        (self.lua / "main.fnl").write_text(prefix + self.original_main[len(first):])

    def cli_process(self, command, *args):
        child = subprocess.Popen([sys.executable, str(self.repo / "tests/live_dev_spawn_observer.py"), command,
                                 "--repo-root", str(self.root), "--timeout", "60", *args],
                                cwd=self.build, env=self.env, stdin=subprocess.DEVNULL,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        # An unreaped direct child cannot have its PID reused. Hold its pidfd
        # immediately, before any communicate/poll can reap it.
        fd = os.pidfd_open(child.pid)
        self.launchers.append((child, fd))
        return child

    def setup_spawn_observer(self):
        self.observer_root = self.base / "observer"
        self.observer_root.mkdir(mode=0o700)
        (self.observer_root / "launches").mkdir(mode=0o700)
        self.app_spawns = {}
        self.observer_socket = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
        self.observer_socket.bind(str(self.observer_root / "spawns.sock"))
        (self.observer_root / "spawns.sock").chmod(0o600)
        self.observer_socket.setblocking(False)
        self.env["SPACE_LIVE_DEV_OBSERVER_ROOT"] = str(self.observer_root)

    def collect_app_spawns(self, require_accounted=False):
        errors = []
        if not hasattr(self, "app_spawns"):
            self.app_spawns = {}
        if hasattr(self, "observer_socket"):
            while True:
                try:
                    payload, ancillary, flags, _address = self.observer_socket.recvmsg(8192, socket.CMSG_SPACE(4))
                except BlockingIOError:
                    break
                fds = array.array("i")
                for level, kind, data in ancillary:
                    if level == socket.SOL_SOCKET and kind == socket.SCM_RIGHTS:
                        fds.frombytes(data[:len(data) - len(data) % fds.itemsize])
                try:
                    assert not flags and len(fds) == 1, "invalid spawn fd transfer"
                    message = json.loads(payload)
                    launch_id, record = message["launch-id"], message["record"]
                    assert len(launch_id) == 32 and all(char in "0123456789abcdef" for char in launch_id)
                    assert record["instance-id"] == "spawn-" + launch_id
                    assert record["checkout-root"] == str(self.root) and record["uid"] == os.getuid()
                    assert launch_id not in self.app_spawns, "duplicate spawn ownership"
                    info = Path(f"/proc/self/fdinfo/{fds[0]}").read_text().splitlines()
                    kernel_pid = int(next(line.split(":", 1)[1] for line in info if line.startswith("Pid:")))
                    assert kernel_pid == record["pid"] or (kernel_pid == -1 and select.select([fds[0]], [], [], 0)[0])
                    self.app_spawns[launch_id] = {"record": record, "pidfd": fds[0]}
                    fds = array.array("i")  # ownership transferred to app_spawns
                except Exception as error:
                    errors.append(f"invalid spawn receipt: {type(error).__name__}")
                finally:
                    for fd in fds:
                        os.close(fd)
        observer_root = getattr(self, "observer_root", self.base / "observer")
        for path in (observer_root / "launches").glob("*.json"):
            try:
                intent = self.module._read_json(path)
                assert intent["checkout-root"] == str(self.root) and intent["launch-id"] == path.stem
                assert intent["state"] in ("pending", "captured", "reported", "no-child", "exited")
                if intent["launch-id"] in self.app_spawns:
                    assert intent["record"] == self.app_spawns[intent["launch-id"]]["record"]
                if require_accounted:
                    assert (intent["state"] in ("no-child", "exited") or intent["launch-id"] in self.app_spawns), f"unaccounted launch {path.stem}"
            except Exception as error:
                errors.append(str(error))
        assert not errors, "fixture cleanup failed: " + "; ".join(errors)

    def stop_app_spawns(self):
        errors = []
        for receipt in self.app_spawns.values():
            fd, record = receipt["pidfd"], receipt["record"]
            if fd is None:
                continue
            try:
                if not select.select([fd], [], [], 0)[0]:
                    self.module._check_process(record)
                    signal.pidfd_send_signal(fd, signal.SIGTERM)
                    self.module._await_exit(record, fd, 5)
            except Exception as error:
                errors.append(f"spawn {record['instance-id']}: {getattr(error, 'code', type(error).__name__)}")
            finally:
                os.close(fd)
                receipt["pidfd"] = None
        assert not errors, "fixture cleanup failed: " + "; ".join(errors)

    def result(self, child, expected=0):
        stdout, stderr = child.communicate(timeout=70)
        self.collect_app_spawns()
        assert not stderr, f"CLI stderr: {stderr}"
        assert child.returncode == expected, f"CLI exit={child.returncode}: {stdout}"
        result = json.loads(stdout)
        assert self.env["LIVE_DEV_SENTINEL_SECRET"] not in stdout
        self.remember(result)
        return result

    def cli(self, command, *args, expected=0):
        return self.result(self.cli_process(command, *args), expected)

    def remember(self, result):
        if isinstance(result, dict) and "pid" in result and "instance-id" in result:
            record = self.module._validate_record(result, self.root)
            self.instances[record["instance-id"]] = record

    def query(self, instance, expression, *, timeout=5):
        # Use the same real Space client and envelope parser, never pyzmq.
        previous = dict(os.environ)
        try:
            os.environ.update(self.env)
            return self.module._remote_code(instance, f"(do (local json (require :json)) (json.dumps {expression}))", timeout)
        finally:
            os.environ.clear()
            os.environ.update(previous)

    def marker(self, instance):
        return self.query(instance, "app.live-dev-fixture-marker")

    def assert_offline(self, instance):
        assert self.query(instance, '((. (require :error-reporting) :enabled?))') is False
        assert self.query(instance, "_G.__live-dev-offline-inits") >= 1

    def wait_instance(self, child):
        previous = dict(os.environ)
        try:
            os.environ.update(self.env)
            instance = self.module._wait_started(self.root, child, 60)
            self.remember(instance)
            return instance
        finally:
            os.environ.clear()
            os.environ.update(previous)

    def ordinary_start(self):
        log = (self.base / "logs/ordinary.log").open("ab")
        try:
            recipe = {"executable": str(self.build / "space"), "argv": ["--no-dotenv", "-m", "main",
                      "--remote-control=auto", "--fixture-custom=quotes\\λ"], "cwd": str(self.build), "environment": self.env}
            def launch(_root, saved):
                return subprocess.Popen([saved["executable"], *saved["argv"]], cwd=saved["cwd"],
                                        env=saved["environment"], stdin=subprocess.DEVNULL,
                                        stdout=log, stderr=log, start_new_session=True)
            child = load_observer(self.repo).observe_launch(self.module, launch, self.observer_root, self.root, recipe)
        finally:
            log.close()
        self.children.append(child)
        return self.wait_instance(child)

    def stop(self, instance):
        # Only registered identities from this fixture, with a verified pidfd.
        try:
            with self.module._verified_pidfd(instance) as fd:
                assert fd is not None, "Linux fixture requires pidfd for safe cleanup"
                signal.pidfd_send_signal(fd, signal.SIGTERM)
                self.module._await_exit(instance, fd, 5)
        except self.module.LiveDevError as error:
            if error.code != "stale-instance":
                raise

    def cleanup(self):
        errors = []
        # Settle every tracked launcher before inspecting the registry: none
        # may create another app after the cleanup snapshot, even on failure.
        for child, fd in self.launchers:
            try:
                try:
                    child.communicate(timeout=70)
                except subprocess.TimeoutExpired:
                    signal.pidfd_send_signal(fd, signal.SIGTERM)
                    try:
                        child.communicate(timeout=5)
                    except subprocess.TimeoutExpired:
                        signal.pidfd_send_signal(fd, signal.SIGKILL)
                        child.communicate(timeout=5)
            except Exception as error:
                errors.append(f"launcher {child.pid}: {type(error).__name__}")
            finally:
                os.close(fd)
        self.launchers.clear()
        try:
            self.collect_app_spawns(require_accounted=True)
        except Exception as error:
            errors.append(f"spawn accounting: {error}")
        try:
            self.stop_app_spawns()
        except Exception as error:
            errors.append(str(error))
        # Include any launched child whose CLI failed before returning identity.
        registry = self.base / "runtime/space-live-dev"
        for path in registry.glob("*/instances/*.json"):
            try:
                self.remember(self.module._read_json(path))
            except Exception as error:
                errors.append(f"record {path.name}: {getattr(error, 'code', type(error).__name__)}")
        for instance in self.instances.values():
            try:
                self.stop(instance)
            except Exception as error:
                errors.append(f"instance {instance['instance-id']}: {getattr(error, 'code', type(error).__name__)}")
        for child in self.children:
            try:
                child.wait(timeout=10)
            except Exception as error:
                errors.append(f"child {child.pid}: {type(error).__name__}")
        if hasattr(self, "observer_socket"):
            self.observer_socket.close()
        assert not errors, "fixture cleanup failed: " + "; ".join(errors)

    def assert_public_privacy(self):
        registry = self.base / "runtime/space-live-dev"
        for path in registry.rglob("*.json"):
            text = path.read_text()
            assert self.env["LIVE_DEV_SENTINEL_SECRET"] not in text
            assert '"environment"' not in text and '"argv"' not in text
            assert path.stat().st_mode & 0o777 == 0o600


def watched_hud_routing(fixture, instance, *, opted_in=False):
    fixture.assert_offline(instance)
    fixture.query(instance, '(do (set _G.__routing-world-manager app.world-manager) true)')
    debug = '(app.hot-reload-controller:debug-state)'
    def wait_for_reload(previous_count):
        deadline = time.monotonic() + 60
        while True:
            remaining = deadline - time.monotonic()
            assert remaining > 0, "watched edit did not execute"
            state = fixture.query(instance, debug, timeout=remaining)
            assert time.monotonic() < deadline, "watched edit observation exceeded deadline"
            if state["reload-count"] > previous_count:
                return state
            time.sleep(0.05)
    generation = fixture.cli("status")["generation"]
    before = fixture.query(instance, debug)
    # Let the ordinary watcher's intentional startup-noise window expire.
    time.sleep(max(0, (before["startup-ignore-ms"] - before["now-ms"]) / 1000) + 5.1)
    hud = fixture.lua / "hud.fnl"
    hud.write_text(hud.read_text() + "\n; fixture watched HUD edit\n")
    after = wait_for_reload(before["reload-count"])
    target = "hud" if opted_in else "app-root"
    assert after["last-target-unit-id"] == target, f"watcher eligibility target: expected {target}, observed {after['last-target-unit-id']}"
    assert fixture.query(instance, '(= app.world-manager _G.__routing-world-manager)') is opted_in, "watcher must replace root unless HUD explicitly opted in"
    watched_generation = generation if opted_in else generation + 1
    assert fixture.cli("status")["generation"] == watched_generation, "only root reload advances generation"
    explicit = fixture.cli("reload")
    assert explicit["status"] == "succeeded"
    assert explicit["generation"] == watched_generation + 1, "explicit root reload must advance generation even with HUD opted in"
    after_explicit = fixture.query(instance, debug)
    assert after_explicit["last-target-unit-id"] == "app-root"
    assert fixture.query(instance, '(not= app.world-manager _G.__routing-world-manager)'), "explicit reload must replace root"
    main = fixture.lua / "main.fnl"
    main.write_text(main.read_text() + "\n; fixture watched root edit\n")
    after_watched_root = wait_for_reload(after_explicit["reload-count"])
    assert after_watched_root["last-target-unit-id"] == "app-root"
    assert fixture.cli("status")["generation"] == watched_generation + 2, "watcher-routed root reload must advance generation"


def manual_reload_roundtrip(fixture, before):
    assert before["mode"] == "watch"
    fixture.cli("manual")
    assert fixture.cli("status")["mode"] == "manual"
    fixture.assert_offline(before)
    # In-flight asynchronous results belong to the process, not the root.
    async_id = fixture.query(before, '(remote_control.create)')
    fixture.query(before, '(do (app.settings.set-value "live_dev_fixture.saved" "kept") true)')
    arguments = fixture.query(before, "_G.arg")
    fixture.write_marker("v2")
    time.sleep(0.4)
    assert fixture.marker(before) == "v1", "manual mode must not react to source writes"
    for marker in ("v2", "v3"):
        fixture.write_marker(marker)
        result = fixture.cli("reload")
        assert result["status"] == "succeeded"
        assert result["instance-id"] == before["instance-id"]
        assert fixture.marker(before) == marker
        request_id = result["request-id"]
        assert (type(request_id) in (int, float) and 0 < request_id < 9007199254740991
                and int(request_id) == request_id)
        assert fixture.cli("status", "--request-id", str(int(request_id))) == result
        assert fixture.query(before, "_G.arg") == arguments
        assert fixture.query(before, '(app.settings.get-value "live_dev_fixture.saved" "missing")') == "kept"
        fixture.assert_offline(before)
    literal = fixture.module._fennel_string(async_id)
    assert fixture.query(before, f'(remote_control.poll {literal} true)')["status"] == "pending"
    assert fixture.query(before, f'(do (remote_control.resolve {literal} "retained") (remote_control.poll {literal}))')["value"] == "retained"
    # Zero-FPS pauses frame work; native control must still service mutations.
    fixture.query(before, '(do (app.set-runtime-performance-control-mode "manual") (app.set-runtime-performance-manual-mode "minimized") true)')
    assert fixture.query(before, "app.runtime-performance-fps-cap") == 0
    idle_reload = fixture.cli("reload")
    assert idle_reload["status"] == "succeeded"
    assert fixture.query(before, "app.runtime-performance-fps-cap") == 0
    return arguments


def recovery_and_blockers(fixture, instance):
    fixture.cli("manual")
    peer = fixture.ordinary_start()
    fixture.cli("manual", "--instance", peer["instance-id"])
    peer_before = fixture.cli("status", "--instance", peer["instance-id"])
    fixture.write_marker("v4")
    # A process-local flag fails the new source load, while old restore fails
    # rollback. A fresh process has no flag and loads the exact same source.
    fixture.query(instance, '(do (set app.__live-dev-fixture-fault? true) (tset (. package.loaded :main) :restore (fn [_snapshot] (error "fixture rollback failure"))) true)')
    result = fixture.cli("reload", expected=1)
    assert result["status"] == "failed"
    assert result["reload"]["rollback"] == "failed"
    assert result["recovery"]["status"] == "succeeded"
    replacement = fixture.cli("status")
    assert replacement["instance-id"] != instance["instance-id"]
    assert fixture.marker(replacement) == "v4"
    fixture.assert_offline(replacement)
    fixture.cli("manual")
    assert fixture.cli("status", "--instance", peer["instance-id"]) == peer_before
    fixture.stop(peer_before)
    assert len(fixture.cli("discover")["instances"]) == 1
    # Updating the client to an uncontrollable version must block duplicate
    # auto-start, not reinterpret a registered live process as missing.
    client = fixture.lua / "tools/remote-control-client.fnl"
    original = client.read_text()
    try:
        client.write_text('{:main (fn [] (error "fixture client unavailable"))}\n')
        blocked = fixture.cli("start", expected=1)
        assert blocked["error"] == "unavailable"
        records = list((fixture.base / "runtime/space-live-dev").glob("*/instances/*.json"))
        assert len(records) == 1
        assert json.loads(records[0].read_text())["pid"] == replacement["pid"]
    finally:
        client.write_text(original)
    return fixture.cli("status")


def prepublication_hang(fixture):
    main = fixture.lua / "main.fnl"
    original = main.read_text()
    offline = "(require :tests.live-dev-offline)\n"
    assert offline in original
    marker = fixture.base / "prepublication-entered"
    hang = (f'(local hang-marker (assert (io.open {json.dumps(str(marker))} "wb")))\n'
            '(hang-marker:write "entered") (hang-marker:close)\n(while true)\n')
    main.write_text(original.replace(offline, offline + hang, 1))
    try:
        launcher = fixture.cli_process("start", "--timeout", "5")
        deadline = time.monotonic() + 20
        while True:
            fixture.collect_app_spawns()
            if fixture.app_spawns and marker.exists() and marker.read_text() == "entered":
                break
            assert launcher.poll() is None, "prepublication app/launcher exited before hang marker"
            assert time.monotonic() < deadline, "prepublication hang did not enter within bounded fixture wait"
            time.sleep(0.02)
        fixture.collect_app_spawns(require_accounted=True)
        assert not list((fixture.base / "runtime/space-live-dev").glob("*/instances/*.json"))
        receipt = next(iter(fixture.app_spawns.values()))
        assert receipt["pidfd"] is not None
        assert not select.select([receipt["pidfd"]], [], [], 0)[0]
        result = fixture.result(launcher, expected=1)
        assert result["error"] == "startup-timeout"
        assert not select.select([receipt["pidfd"]], [], [], 0)[0], "timeout child must still be alive"
        retry = fixture.cli("start", expected=1)
        assert retry["error"] == "startup-in-progress"
        fixture.collect_app_spawns(require_accounted=True)
        assert len(fixture.app_spawns) == 1, "timeout retry launched a duplicate prepublication app"
        fixture.stop_app_spawns()
    finally:
        main.write_text(original)


def two_instance_restart(fixture, selected):
    other = fixture.ordinary_start()
    fixture.cli("manual", "--instance", other["instance-id"])
    before_other = fixture.cli("status", "--instance", other["instance-id"])
    replacement = fixture.cli("restart", "--instance", selected["instance-id"])
    assert replacement["instance-id"] != selected["instance-id"]
    assert fixture.cli("status", "--instance", other["instance-id"]) == before_other
    assert len(fixture.cli("discover")["instances"]) == 2
    fixture.stop(before_other)
    assert len(fixture.cli("discover")["instances"]) == 1
    return replacement


def run_scenarios(fixture):
    prepublication_hang(fixture)
    # Two independent CLI processes race on a completely absent fixture app.
    starts = [fixture.cli_process("start"), fixture.cli_process("start")]
    before, concurrent = [fixture.result(child) for child in starts]
    assert before["instance-id"] == concurrent["instance-id"]
    assert len(fixture.cli("discover")["instances"]) == 1
    assert Path(before["checkout-root"]) == fixture.root
    assert Path(before["native-source-root"]) != fixture.root
    watched_hud_routing(fixture, before)
    fixture.cli("manual")
    fixture.narrow_reload_unit_ids = ["hud"]
    fixture.write_marker("v1")
    before = fixture.cli("restart")
    watched_hud_routing(fixture, before, opted_in=True)
    before = two_instance_restart(fixture, before)
    arguments = manual_reload_roundtrip(fixture, before)
    rejected = fixture.cli("restart", "--rebuild", expected=1)
    assert rejected["error"] == "native-source-mismatch"
    assert fixture.cli("status")["instance-id"] == before["instance-id"]
    after = fixture.cli("restart")
    assert after["instance-id"] != before["instance-id"]
    assert fixture.marker(after) == "v3"
    assert fixture.query(after, "_G.arg") == arguments
    assert fixture.query(after, '(app.settings.get-value "live_dev_fixture.saved" "missing")') == "kept"
    fixture.assert_offline(after)
    fixture.stop(after)
    # A manually launched watcher-enabled app has extra native argv. Select
    # it explicitly instead of reusing the previous stale persisted selection.
    ordinary = fixture.ordinary_start()
    fixture.cli("select", "--instance", ordinary["instance-id"])
    custom_args = fixture.query(ordinary, "_G.arg")
    assert custom_args == {"0": "main", "1": "--remote-control=auto",
                           "2": "--fixture-custom=quotes\\λ"}
    restarted = fixture.cli("restart")
    assert fixture.query(restarted, "_G.arg") == custom_args
    # Preserved infrastructure is an explicit restart boundary.
    fixture.cli("manual")
    boundary = fixture.lua / "live-dev-runtime.fnl"
    boundary.write_text(boundary.read_text() + "\n; fixture restart boundary\n")
    failed = fixture.cli("reload", expected=1)
    assert failed["reload"]["phase"] == "restart-required"
    assert "recovery" not in failed
    restarted = fixture.cli("restart")
    final = recovery_and_blockers(fixture, restarted)
    assert fixture.cli("select", "--instance", "stale-id", expected=1)["error"] == "stale-selection"
    fixture.assert_offline(final)
    fixture.assert_public_privacy()
    fixture.stop(final)
    # Saved preference is not an explicit stale target after the app exits.
    automatic = fixture.cli("start")
    assert automatic["instance-id"] != final["instance-id"]
    assert fixture.marker(automatic) == "v4"
    fixture.assert_offline(automatic)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--space", type=Path, required=True)
    parser.add_argument("--repo-root", type=Path, required=True)
    args = parser.parse_args()
    if not sys.platform.startswith("linux") or not os.environ.get("DISPLAY"):
        parser.error("live-dev integration requires Linux and a display; run under xvfb-run")
    # No native core dumps, even for deliberate failure injection.
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    Path("/tmp/space").mkdir(mode=0o700, exist_ok=True)
    directory = tempfile.mkdtemp(prefix="ld-", dir="/tmp/space")
    try:
        fixture = Fixture(directory, args.repo_root.resolve(), args.space.resolve())
        try:
            run_scenarios(fixture)
        finally:
            fixture.cleanup()
    except BaseException:
        print(f"Live-dev diagnostic fixture retained: {directory}", file=sys.stderr)
        raise
    else:
        shutil.rmtree(directory)
    print("live-dev real-app integration: all scenarios passed (offline, isolated)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
