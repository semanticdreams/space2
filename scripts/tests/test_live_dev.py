"""Focused Linux lifecycle contract tests (no user app or registry access)."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import threading
import time
import tempfile
import uuid
from concurrent.futures import ThreadPoolExecutor
from contextlib import contextmanager

import pytest


@pytest.fixture
def live_dev():
    path = Path(__file__).parents[1] / "live_dev.py"
    assert path.exists(), "Task 3 lifecycle CLI is not implemented"
    spec = importlib.util.spec_from_file_location("live_dev", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


@pytest.fixture
def checkout(tmp_path, monkeypatch):
    # Short private roots keep real Unix sockets/XDG registries isolated too.
    Path("/tmp/space").mkdir(mode=0o700, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="ldu-", dir="/tmp/space") as directory:
        root = Path(directory) / "checkout"
        root.mkdir()
        subprocess.run(["git", "init", "-q", str(root)], check=True)
        runtime = Path(directory) / "run"
        runtime.mkdir(mode=0o700)
        monkeypatch.setenv("XDG_RUNTIME_DIR", str(runtime))
        yield root


def record_for(live_dev, root):
    exe = str(Path("/proc/self/exe").resolve())
    return {"schema-version": 1, "instance-id": "test-instance", "pid": os.getpid(),
            "uid": os.getuid(), "boot-id": Path("/proc/sys/kernel/random/boot_id").read_text().strip(),
            "process-start": Path("/proc/self/stat").read_text().rsplit(")", 1)[1].split()[19],
            "executable": exe, "executable-identity": live_dev._executable_identity(Path(exe)),
            "checkout-root": str(root), "source-root": str(root / "assets/lua"),
            "main-source": str(root / "assets/lua/main.fnl"),
            "native-source-root": str(root), "native-build-root": str(root / "build"),
            "build-profile": "full", "cef-enabled": True,
            "endpoint": "ipc://" + str(live_dev.runtime_directory(os.environ) / "s-test"),
            "ready": True, "faulted": False, "generation": 1, "mode": "manual",
            "next-request-id": 1, "capabilities": ["manual", "reload", "quit", "launch-recipe"]}


def publish(live_dev, root, record):
    directory = live_dev._partition(root) / "instances"
    directory.mkdir(mode=0o700, exist_ok=True)
    path = directory / (record["instance-id"] + ".json")
    path.write_text(json.dumps(record))
    path.chmod(0o600)
    return path


def test_multiple_instances_require_selection(live_dev):
    with pytest.raises(live_dev.LiveDevError) as caught:
        live_dev.choose_instance([{"instance-id": "a"}, {"instance-id": "b"}], None)
    assert caught.value.code == "ambiguous-instance"
    assert len(caught.value.details["candidates"]) == 2


def test_selection_never_falls_back(live_dev):
    with pytest.raises(live_dev.LiveDevError, match="stale-selection"):
        live_dev.choose_instance([{"instance-id": "b"}], {"instance-id": "a"})
    assert live_dev.choose_instance([{"instance-id": "b"}], "b")["instance-id"] == "b"


def test_git_canonical_checkout_and_symlink(live_dev, checkout, tmp_path):
    link = tmp_path / "alias"
    link.symlink_to(checkout, target_is_directory=True)
    assert live_dev.canonical_checkout(link) == checkout
    with pytest.raises(live_dev.LiveDevError):
        live_dev.canonical_checkout(tmp_path)


def test_runtime_paths_reject_symlinks_and_permissions(live_dev, tmp_path):
    target = tmp_path / "target"
    target.mkdir(mode=0o700)
    link = tmp_path / "link"
    link.symlink_to(target)
    with pytest.raises(live_dev.LiveDevError):
        live_dev.runtime_directory({"XDG_RUNTIME_DIR": str(link)})
    target.chmod(0o755)
    with pytest.raises(live_dev.LiveDevError):
        live_dev.runtime_directory({"XDG_RUNTIME_DIR": str(target)})


def test_discovery_handshake_and_sibling_exclusion(live_dev, checkout, tmp_path, monkeypatch):
    record = record_for(live_dev, checkout)
    publish(live_dev, checkout, record)
    sibling = tmp_path / "sibling"
    sibling.mkdir()
    subprocess.run(["git", "init", "-q", str(sibling)], check=True)
    foreign = record_for(live_dev, sibling)
    foreign["instance-id"] = "sibling"
    publish(live_dev, sibling, foreign)
    calls = []
    def rpc(instance, request, timeout):
        calls.append(instance["instance-id"])
        return record
    monkeypatch.setattr(live_dev, "remote_request", rpc)
    assert live_dev.discover(checkout) == [record]
    assert calls == ["test-instance"]


@pytest.mark.parametrize("field,value", [("process-start", "0"), ("boot-id", "00000000-0000-4000-8000-000000000000")])
def test_proven_reused_identity_is_pruned(live_dev, checkout, field, value):
    record = record_for(live_dev, checkout)
    record[field] = value
    path = publish(live_dev, checkout, record)
    assert live_dev.discover(checkout) == []
    assert not path.exists()


@pytest.mark.parametrize("change", ["endpoint", "pid", "executable-identity"])
def test_handshake_identity_mismatch_is_not_absence(live_dev, checkout, monkeypatch, change):
    record = record_for(live_dev, checkout)
    path = publish(live_dev, checkout, record)
    reply = dict(record, **{change: "wrong"})
    monkeypatch.setattr(live_dev, "remote_request", lambda *args: reply)
    with pytest.raises(live_dev.LiveDevError, match="unavailable"):
        live_dev.discover(checkout)
    assert path.exists()


def test_unavailable_app_blocks_start(live_dev, checkout, monkeypatch):
    record = record_for(live_dev, checkout)
    path = publish(live_dev, checkout, record)
    def unavailable(*args):
        raise live_dev.LiveDevError("remote-timeout")
    monkeypatch.setattr(live_dev, "remote_request", unavailable)
    monkeypatch.setattr(live_dev, "_launch", lambda *a, **kw: pytest.fail("duplicate launch"))
    with pytest.raises(live_dev.LiveDevError, match="unavailable"):
        live_dev.ensure_started(checkout)
    assert path.exists()


@pytest.mark.parametrize("kind", ["malformed", "foreign", "symlink", "public-mode"])
def test_uncertain_records_block_discovery(live_dev, checkout, kind):
    record = record_for(live_dev, checkout)
    path = publish(live_dev, checkout, record)
    if kind == "malformed":
        path.write_text("{")
    elif kind == "foreign":
        record["checkout-root"] = "/somewhere-else"
        path.write_text(json.dumps(record))
    elif kind == "symlink":
        path.rename(path.with_suffix(".target"))
        path.symlink_to(path.with_suffix(".target"))
    else:
        path.chmod(0o644)
    with pytest.raises(live_dev.LiveDevError):
        live_dev.discover(checkout)
    assert path.exists()


def test_fennel_string_round_trip(live_dev):
    text = 'quote"\nback\\slash λ 🐟'
    encoded = live_dev._fennel_string(text)
    assert encoded[0] == encoded[-1] == '"'
    assert bytes(int(part) for part in encoded[1:-1].split("\\")[1:]).decode() == text


@pytest.mark.parametrize("returncode,stdout,code", [(0, "error SECRET_RECIPE", "remote-error"),
                                                  (1, "SECRET_RECIPE", "remote-failed"),
                                                  (0, "ok not json", "remote-protocol")])
def test_rpc_never_exposes_private_errors(live_dev, checkout, monkeypatch, returncode, stdout, code):
    record = record_for(live_dev, checkout)
    monkeypatch.setattr(live_dev.subprocess, "run", lambda *a, **k: subprocess.CompletedProcess(a, returncode, stdout, "SECRET_RECIPE"))
    with pytest.raises(live_dev.LiveDevError) as caught:
        live_dev.remote_request(record, {"action": "launch-recipe"}, 1)
    assert caught.value.code == code
    assert "SECRET_RECIPE" not in str(caught.value)
    assert "SECRET_RECIPE" not in json.dumps(caught.value.details)


def test_rpc_uses_selected_binary_absolute_paths_and_json(live_dev, checkout, monkeypatch):
    record = record_for(live_dev, checkout)
    def run(args, **kwargs):
        assert args[0] == record["executable"]
        assert args[1:3] == ["-m", "tools.remote-control-client:main"]
        assert kwargs["env"]["FENNEL_PATH"].startswith(record["source-root"] + "/")
        assert "(json.loads " in args[-1]
        assert "(json.dumps " in args[-1]
        assert kwargs["cwd"] == record["native-build-root"]
        return subprocess.CompletedProcess(args, 0, 'ok {"status":"succeeded"}\n', "")
    monkeypatch.setattr(live_dev.subprocess, "run", run)
    assert live_dev.remote_request(record, {"action": "status", "value": '"\n\\λ'}, 1)["status"] == "succeeded"


def test_launch_preserves_user_environment(live_dev, checkout, monkeypatch):
    (checkout / "build").mkdir()
    (checkout / "build/space").symlink_to(sys.executable)
    monkeypatch.setenv("SENTINEL_SECRET", "never-publish")
    monkeypatch.setenv("XDG_DATA_HOME", "/normal/user/settings")
    monkeypatch.delenv("SPACE_DISABLE_AUDIO", raising=False)
    recipe = live_dev._default_recipe(checkout)
    assert recipe["environment"]["XDG_DATA_HOME"] == "/normal/user/settings"
    assert "SPACE_DISABLE_AUDIO" not in recipe["environment"]
    assert recipe["argv"] == ["-m", "main", "--remote-control=auto"]
    assert recipe["cwd"] == str(checkout / "build")
    assert "SENTINEL_SECRET" in recipe["environment"]


def test_launch_retains_inherited_asset_fallback(live_dev, checkout, monkeypatch):
    (checkout / "build").mkdir()
    (checkout / "build/space").symlink_to(sys.executable)
    monkeypatch.setenv("SPACE_ASSETS_PATH", "/custom/assets")
    recipe = live_dev._default_recipe(checkout)
    assert recipe["environment"]["SPACE_ASSETS_PATH"] == str(checkout / "assets") + os.pathsep + "/custom/assets"


def test_serialized_start_rediscovery_avoids_launch(live_dev, checkout, monkeypatch):
    record = record_for(live_dev, checkout)
    monkeypatch.setattr(live_dev, "discover", lambda *a, **k: [record])
    monkeypatch.setattr(live_dev, "_launch", lambda *a, **kw: pytest.fail("duplicate launch"))
    assert live_dev.ensure_started(checkout) == record


def test_lock_is_bounded(live_dev, checkout):
    with live_dev._checkout_lock(checkout, 1):
        with pytest.raises(live_dev.LiveDevError, match="lock-timeout"):
            with live_dev._checkout_lock(checkout, 0.01):
                pytest.fail("lock acquired twice")


def test_selection_file_contains_only_identity(live_dev, checkout):
    record = record_for(live_dev, checkout)
    record["environment"] = {"SECRET": "never-publish"}
    live_dev._save_selection(checkout, record)
    text = (live_dev._partition(checkout) / "selection.json").read_text()
    assert "never-publish" not in text
    assert "environment" not in text
    assert json.loads(text)["process-start"] == record["process-start"]


def write_cache(root, source, profile="full", cef="ON"):
    root.mkdir(exist_ok=True)
    (root / "CMakeCache.txt").write_text(f"CMAKE_HOME_DIRECTORY:INTERNAL={source}\nSPACE_BUILD_PROFILE:STRING={profile}\nSPACE_ENABLE_CEF:BOOL={cef}\n")


def test_rebuild_preserves_full_cef_profile(live_dev, checkout, monkeypatch):
    record = record_for(live_dev, checkout)
    write_cache(checkout / "build", checkout)
    calls = []
    monkeypatch.setattr(live_dev, "_build", lambda args, cwd: calls.append((args, cwd)))
    live_dev._rebuild(checkout, record)
    assert calls[0][0][:4] == ["cmake", "--build", str(checkout / "build"), "--parallel"]
    assert not any("minimal" in arg for arg in calls[0][0])


def test_rebuild_rejects_fixture_native_mismatch(live_dev, checkout):
    record = record_for(live_dev, checkout)
    record["native-source-root"] = "/different/native/source"
    with pytest.raises(live_dev.LiveDevError, match="native-source-mismatch"):
        live_dev._rebuild(checkout, record)


def test_missing_binary_uses_existing_cache_without_configuration(live_dev, checkout, monkeypatch):
    write_cache(checkout / "build", checkout)
    calls = []
    def build(args, cwd):
        calls.append(args)
        (checkout / "build/space").symlink_to(sys.executable)
    monkeypatch.setattr(live_dev, "_build", build)
    live_dev._default_recipe(checkout)
    assert calls == [["cmake", "--build", str(checkout / "build"), "--parallel", os.environ.get("BUILD_JOBS", "1")]]


def test_reload_failure_recovers_once_and_stays_failure(live_dev, checkout, monkeypatch, capsys):
    record = record_for(live_dev, checkout)
    monkeypatch.setattr(live_dev, "discover", lambda *a, **k: [record])
    monkeypatch.setattr(live_dev, "_load_selection", lambda *a: None)
    monkeypatch.setattr(live_dev, "_recipe", lambda *a: {"environment": {"SECRET": "never-publish"}})
    monkeypatch.setattr(live_dev, "_operate", lambda *a: {"status": "failed", "rollback": "failed", "recovery-required": True})
    calls = []
    def restart(*args, **kwargs):
        calls.append(args)
        return dict(record, **{"instance-id": "replacement"})
    monkeypatch.setattr(live_dev, "restart_instance", restart)
    assert live_dev.main(["reload", "--repo-root", str(checkout)]) == 1
    out = json.loads(capsys.readouterr().out)
    assert out["status"] == "failed"
    assert out["reload"]["rollback"] == "failed"
    assert out["recovery"]["instance-id"] == "replacement"
    assert len(calls) == 1
    assert "never-publish" not in json.dumps(out)


def test_updated_executable_blocks_duplicate_start(live_dev, checkout):
    record = record_for(live_dev, checkout)
    parts = record["executable-identity"].split(":")
    parts[1] = str(int(parts[1]) + 1)
    record["executable-identity"] = ":".join(parts)
    path = publish(live_dev, checkout, record)
    with pytest.raises(live_dev.LiveDevError, match="unavailable"):
        live_dev.ensure_started(checkout)
    assert path.exists()


def test_start_waits_through_child_initialization(live_dev, checkout, monkeypatch):
    record = record_for(live_dev, checkout)
    attempts = []
    def discovery(*args, **kwargs):
        attempts.append(True)
        if len(attempts) == 1:
            raise live_dev.LiveDevError("unavailable", **{"instance-id": record["instance-id"]})
        return [record]
    monkeypatch.setattr(live_dev, "discover", discovery)
    class Child:
        pid = os.getpid()
        def poll(self):
            return None
    assert live_dev._wait_started(checkout, Child(), 1) == record
    assert len(attempts) == 2


def test_restart_rejects_profile_mismatch_before_quit(live_dev, checkout, monkeypatch, capsys):
    record = record_for(live_dev, checkout)
    write_cache(checkout / "build", checkout, profile="minimal", cef="OFF")
    monkeypatch.setattr(live_dev, "discover", lambda *a, **k: [record])
    monkeypatch.setattr(live_dev, "_load_selection", lambda *a: None)
    monkeypatch.setattr(live_dev, "_recipe", lambda *a: {})
    monkeypatch.setattr(live_dev, "restart_instance", lambda *a, **kw: pytest.fail("stopped before validating profile"))
    assert live_dev.main(["restart", "--rebuild", "--repo-root", str(checkout)]) == 1
    assert json.loads(capsys.readouterr().out)["error"] == "build-profile-mismatch"


def test_restart_after_verified_app_exit_uses_recipe(live_dev, checkout, monkeypatch):
    record = record_for(live_dev, checkout)
    record["process-start"] = "0"
    replacement = dict(record, **{"instance-id": "replacement", "process-start": "1"})
    recipe = {"executable": record["executable"], "cwd": str(checkout),
              "argv": ["-m", "main", "--custom", 'quoted λ'], "environment": {"SECRET": "private"}}
    monkeypatch.setattr(live_dev, "discover", lambda *a, **k: [])
    launches = []
    def launch_and_wait(root, saved, *args):
        launches.append(saved)
        return replacement
    monkeypatch.setattr(live_dev, "_launch_and_wait", launch_and_wait)
    assert live_dev.restart_instance(checkout, record, recipe) == replacement
    assert launches == [recipe]


def test_rpc_timeout_is_nonzero_and_private(live_dev, checkout, monkeypatch):
    record = record_for(live_dev, checkout)
    def timeout(*args, **kwargs):
        raise subprocess.TimeoutExpired(["SECRET_RECIPE"], 1, output="SECRET_RECIPE")
    monkeypatch.setattr(live_dev.subprocess, "run", timeout)
    with pytest.raises(live_dev.LiveDevError, match="remote-timeout") as caught:
        live_dev.remote_request(record, {"action": "launch-recipe"}, 0.1)
    assert "SECRET" not in str(caught.value)


def test_exact_recipe_launch_is_detached_and_private(live_dev, checkout, monkeypatch):
    recipe = {"executable": sys.executable, "argv": ["-m", "main", "--keep=λ"],
              "cwd": str(checkout), "environment": {"SECRET": "do-not-publish"}}
    def popen(args, **kwargs):
        assert args == [sys.executable, *recipe["argv"]]
        assert kwargs["env"] == recipe["environment"]
        assert kwargs["cwd"] == recipe["cwd"]
        assert kwargs["start_new_session"] is True
        assert kwargs["stdin"] == subprocess.DEVNULL
        assert kwargs["stdout"] == kwargs["stderr"]
        assert os.fstat(kwargs["stdout"]).st_mode & 0o777 == 0o600
        return "child"
    monkeypatch.setattr(live_dev.subprocess, "Popen", popen)
    assert live_dev._launch(checkout, recipe) == "child"


def test_pidfd_unavailable_refuses_pid_only_escalation(live_dev, checkout, monkeypatch):
    record = record_for(live_dev, checkout)
    monkeypatch.setattr(live_dev.os, "kill", lambda *a: pytest.fail("unsafe PID-only signaling"))
    with pytest.raises(live_dev.LiveDevError, match="unsafe-stop"):
        live_dev._await_exit(record, None, 0.01)


def test_recipe_payload_is_never_public(live_dev, checkout, monkeypatch, capsys):
    record = record_for(live_dev, checkout)
    monkeypatch.setattr(live_dev, "discover", lambda *a, **k: [record])
    monkeypatch.setattr(live_dev, "_load_selection", lambda *a: None)
    monkeypatch.setattr(live_dev, "remote_request", lambda *a: {"environment": {"SECRET": "do-not-publish"}})
    assert live_dev.main(["restart", "--repo-root", str(checkout)]) == 1
    assert "do-not-publish" not in capsys.readouterr().out


def test_native_empty_argv_recipe_preserves_zero_arguments(live_dev, checkout, monkeypatch):
    record = record_for(live_dev, checkout)
    # Native launch-recipe uses a Lua table. Space JSON emits [] for an empty
    # table, including the legitimate './space' normal-entry argv case.
    recipe = {"executable": record["executable"], "cwd": str(checkout),
              "argv": [], "environment": {"PRIVATE": "kept-in-memory"}}
    monkeypatch.setattr(live_dev, "remote_request", lambda *a: recipe)
    decoded = live_dev._recipe(record, 1)
    assert decoded["argv"] == []
    calls = []
    monkeypatch.setattr(live_dev.subprocess, "Popen", lambda args, **kw: calls.append((args, kw)))
    live_dev._launch(checkout, decoded)
    assert calls[0][0] == [record["executable"]]
    assert calls[0][1]["env"] == recipe["environment"]


def test_linux_live_ctest_and_local_unit_gate_are_registered():
    root = Path(__file__).parents[2]
    cmake = (root / "CMakeLists.txt").read_text()
    makefile = (root / "Makefile").read_text()
    assert "NAME space_live_dev_integration" in cmake
    live = cmake.split("NAME space_live_dev_integration", 1)[1].split("endif()", 1)[0]
    assert "tests/test_live_dev_integration.py" in live
    assert "FIXTURES_REQUIRED space_constraints" in live
    assert "--space $<TARGET_FILE:${SPACE_TEST_COMMAND_TARGET}>" in live
    assert "scripts/tests/test_live_dev.py" in makefile.split("opencode-check:", 1)[1]
    assert "--remote-control=auto" in makefile.split("run:", 1)[1].split("docs:", 1)[0]


def integral_record(live_dev, root):
    record = record_for(live_dev, root)
    record["pid"] = float(record["pid"])
    record["uid"] = float(record["uid"])
    return json.loads(json.dumps(record))


def test_integral_json_record_status_identity(live_dev, checkout, monkeypatch):
    record = integral_record(live_dev, checkout)
    publish(live_dev, checkout, record)
    monkeypatch.setattr(live_dev, "remote_request", lambda *a: dict(record))
    found = live_dev.discover(checkout)
    assert len(found) == 1
    assert type(found[0]["pid"]) is int and found[0]["pid"] == os.getpid()
    assert type(found[0]["uid"]) is int and found[0]["uid"] == os.getuid()


def test_integral_json_selection_identity(live_dev, checkout):
    record = integral_record(live_dev, checkout)
    selected = {key: record[key] for key in live_dev.IDENTITY}
    live_dev._write_json(live_dev._partition(checkout) / "selection.json", selected)
    loaded = live_dev._load_selection(checkout)
    assert type(loaded["pid"]) is int and type(loaded["uid"]) is int
    assert live_dev.choose_instance([record_for(live_dev, checkout)], loaded)["pid"] == os.getpid()
    loaded["process-start"] = "0"
    with pytest.raises(live_dev.LiveDevError, match="stale-selection"):
        live_dev.choose_instance([record_for(live_dev, checkout)], loaded)


def test_integral_json_pidfd_identity(live_dev, checkout, monkeypatch):
    record = integral_record(live_dev, checkout)
    opened = []
    original_open = os.pidfd_open
    def pidfd_open(pid):
        assert type(pid) is int
        opened.append(pid)
        return original_open(pid)
    monkeypatch.setattr(live_dev.os, "pidfd_open", pidfd_open)
    with live_dev._verified_pidfd(record) as fd:
        assert fd is not None
    assert opened == [os.getpid()]


@pytest.mark.parametrize("field,values", [
    ("pid", [True, False, "1", float("nan"), float("inf"), float("-inf"), 1.5, -1, 0, 2147483648, 2147483648.0]),
    ("uid", [True, False, "1000", float("nan"), float("inf"), float("-inf"), 1.5, -1, 4294967295, 4294967295.0]),
])
def test_numeric_identity_rejects_invalid(live_dev, checkout, monkeypatch, field, values):
    monkeypatch.setattr(live_dev.os, "pidfd_open", lambda *a: pytest.fail("invalid number reached kernel"))
    for value in values:
        record = record_for(live_dev, checkout)
        record[field] = value
        with pytest.raises(live_dev.LiveDevError, match="invalid-record"):
            with live_dev._verified_pidfd(record):
                pytest.fail("invalid number accepted")


@pytest.mark.parametrize("pid,uid", [(1, 0), (1.0, 0.0), (2147483647, 4294967294), (2147483647.0, 4294967294.0)])
def test_numeric_identity_bounds(live_dev, pid, uid):
    normalized = live_dev._identity_numbers({"pid": pid, "uid": uid})
    assert normalized == {"pid": int(pid), "uid": int(uid)}
    assert type(normalized["pid"]) is type(normalized["uid"]) is int


@pytest.mark.parametrize("field,value,code", [("uid", -1, "invalid-record"),
    ("boot-id", "00000000-0000-4000-8000-000000000000", "stale-instance"), ("process-start", "0", "stale-instance"),
    ("executable-identity", "0:0:0:0:0", "unavailable")])
def test_numeric_identity_mismatch_not_coerced(live_dev, checkout, monkeypatch, field, value, code):
    record = integral_record(live_dev, checkout)
    record[field] = value
    monkeypatch.setattr(live_dev, "remote_request", lambda *a: pytest.fail("bad identity reached RPC"))
    with pytest.raises(live_dev.LiveDevError, match=code):
        live_dev.verify_instance(record, checkout)


def test_numeric_identity_wrong_kernel_uid(live_dev, checkout):
    record = integral_record(live_dev, checkout)
    record["uid"] = float(os.getuid() + 1)
    with pytest.raises(live_dev.LiveDevError, match="invalid-record"):
        live_dev.verify_instance(record, checkout)


def integration_module():
    path = Path(__file__).parents[2] / "tests/test_live_dev_integration.py"
    spec = importlib.util.spec_from_file_location("live_dev_integration", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def cleanup_fixture(live_dev, checkout):
    fixture = object.__new__(integration_module().Fixture)
    fixture.module = live_dev
    fixture.root = checkout
    fixture.base = checkout.parent
    fixture.repo = Path(__file__).parents[2]
    fixture.build = checkout
    fixture.env = dict(os.environ)
    fixture.instances = {}
    fixture.children = []
    fixture.launchers = []
    fixture.setup_spawn_observer()
    return fixture


def cleanup_record(fixture, record):
    directory = fixture.base / "runtime/space-live-dev/partition/instances"
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    path = directory / (record["instance-id"] + ".json")
    path.write_text(json.dumps(record))
    path.chmod(0o600)


@pytest.mark.parametrize("invalid_record", [False, True])
def test_fixture_ordinary_readiness_restores_env_and_preserves_errors(live_dev, checkout, monkeypatch, invalid_record):
    fixture = cleanup_fixture(live_dev, checkout)
    fixture.env["LIVE_DEV_READINESS_SENTINEL"] = "isolated"
    before = dict(os.environ)
    child = subprocess.Popen([sys.executable, "-c", "import sys; sys.stdin.buffer.read()"], stdin=subprocess.PIPE)
    ready = child_record(live_dev, checkout, child)
    peer = dict(record_for(live_dev, checkout), **{"instance-id": "other-ready-instance"})
    observed = []
    def discover(*args, **kwargs):
        observed.append(os.environ.get("LIVE_DEV_READINESS_SENTINEL"))
        if invalid_record:
            raise live_dev.LiveDevError("invalid-record")
        if len(observed) == 1:
            raise live_dev.LiveDevError("unavailable")
        return [peer] if len(observed) == 2 else [peer, ready]
    def cli(command):
        assert command == "discover"
        try:
            return {"instances": live_dev.discover(checkout)}
        except live_dev.LiveDevError as error:
            # The old fixture aborts here instead of using its bounded wait.
            raise AssertionError("CLI exit=1: " + error.code) from None
    monkeypatch.setattr(live_dev, "discover", discover)
    monkeypatch.setattr(fixture, "cli", cli)
    try:
        if invalid_record:
            with pytest.raises(live_dev.LiveDevError, match="invalid-record"):
                fixture.wait_instance(child)
            assert observed == ["isolated"], "invalid metadata must fail immediately"
            assert child.poll() is None, "readiness failure must not stop the owned child"
        else:
            assert fixture.wait_instance(child) == ready
            assert fixture.instances == {ready["instance-id"]: ready}
            assert observed == ["isolated"] * 3, "wait must tolerate unavailable but not select the healthy peer"
        assert dict(os.environ) == before, "fixture environment must be restored on success and failure"
    finally:
        child.communicate(b"x", timeout=5)
        fixture.cleanup()


def test_fixture_cleanup_normalizes_owned_records(live_dev, checkout, monkeypatch):
    fixture = cleanup_fixture(live_dev, checkout)
    record = integral_record(live_dev, checkout)
    cleanup_record(fixture, record)
    stopped = []
    def stop(instance):
        assert type(instance["pid"]) is type(instance["uid"]) is int
        stopped.append(instance["instance-id"])
    monkeypatch.setattr(fixture, "stop", stop)
    fixture.cleanup()
    assert stopped == [record["instance-id"]]


def test_fixture_cleanup_rejects_foreign_record(live_dev, checkout, monkeypatch):
    fixture = cleanup_fixture(live_dev, checkout)
    record = integral_record(live_dev, checkout)
    record["checkout-root"] = "/foreign"
    cleanup_record(fixture, record)
    monkeypatch.setattr(fixture, "stop", lambda *a: pytest.fail("foreign record signaled"))
    with pytest.raises(AssertionError, match="cleanup failed"):
        fixture.cleanup()


def test_fixture_cleanup_attempts_all_known_identities(live_dev, checkout, monkeypatch):
    fixture = cleanup_fixture(live_dev, checkout)
    first = record_for(live_dev, checkout)
    second = dict(first, **{"instance-id": "second"})
    fixture.instances = {"first": first, "second": second}
    stopped = []
    waited = []
    class Child:
        def wait(self, **kwargs):
            waited.append(True)
    fixture.children = [Child()]
    def stop(instance):
        stopped.append(instance["instance-id"])
        if len(stopped) == 1:
            raise live_dev.LiveDevError("injected-stop-failure")
    monkeypatch.setattr(fixture, "stop", stop)
    with pytest.raises(AssertionError, match="cleanup failed"):
        fixture.cleanup()
    assert stopped == [first["instance-id"], second["instance-id"]]
    assert waited == [True]


def test_fixture_cleanup_tracks_and_settles_launchers(live_dev, checkout):
    fixture = cleanup_fixture(live_dev, checkout)
    child = fixture.cli_process("discover")
    assert fixture.launchers, "direct launcher ownership must be tracked immediately"
    fixture.cleanup()
    assert child.poll() == 0


@pytest.mark.parametrize("field,value", [("boot-id", "00000000-0000-4000-8000-000000000000"), ("process-start", "0"), ("uid", -1)])
def test_fixture_cleanup_never_signals_reused_identity(live_dev, checkout, monkeypatch, field, value):
    fixture = cleanup_fixture(live_dev, checkout)
    record = integral_record(live_dev, checkout)
    record[field] = value
    monkeypatch.setattr(live_dev.signal, "pidfd_send_signal", lambda *a: pytest.fail("unverified signal"))
    if field == "uid":
        with pytest.raises(live_dev.LiveDevError, match="invalid-record"):
            fixture.stop(record)
    else:
        fixture.stop(record)


def test_fixture_cold_start_budget_preserves_production_default(live_dev, checkout, monkeypatch, capsys):
    fixture = cleanup_fixture(live_dev, checkout)
    called = []
    class Child:
        pid = os.getpid()
    def popen(args, **kwargs):
        called.append(args)
        return Child()
    monkeypatch.setattr(subprocess, "Popen", popen)
    fixture.cli_process("start")
    args = called[0]
    assert args[args.index("--timeout") + 1] == "60"
    for _child, fd in fixture.launchers:
        os.close(fd)
    monkeypatch.setattr(live_dev, "canonical_checkout", lambda *a: checkout)
    monkeypatch.setattr(live_dev, "_load_selection", lambda *a: None)
    timeouts = []
    def started(root, timeout, selection, saved_selection=None):
        timeouts.append(timeout)
        return record_for(live_dev, checkout)
    monkeypatch.setattr(live_dev, "ensure_started", started)
    assert live_dev.main(["start", "--repo-root", str(checkout)]) == 0
    assert timeouts == [30]
    capsys.readouterr()


def test_operation_poll_honors_remaining_deadline(live_dev, checkout, monkeypatch):
    instance = record_for(live_dev, checkout)
    clock = [100.0]
    monkeypatch.setattr(live_dev.time, "monotonic", lambda: clock[0])
    monkeypatch.setattr(live_dev.time, "sleep", lambda seconds: clock.__setitem__(0, clock[0] + seconds))
    submitted = []
    polls = []
    def rpc(selected, request, timeout):
        assert selected == instance
        if request["action"] == "status":
            return {"next-request-id": 7}
        if request["action"] == "reload":
            submitted.append(request)
            clock[0] += 1
            return {"status": "pending", "request-id": 7, "action": "reload", "instance-id": instance["instance-id"]}
        assert request == {"action": "operation", "request-id": 7}
        polls.append(timeout)
        assert timeout <= 110 - clock[0], "poll must recompute budget after sleep"
        if timeout <= 2:
            raise live_dev.LiveDevError("remote-timeout")
        return {"status": "succeeded", "request-id": 7, "action": "reload", "instance-id": instance["instance-id"]}
    monkeypatch.setattr(live_dev, "remote_request", rpc)
    assert live_dev._operate(instance, "reload", 10)["status"] == "succeeded"
    assert submitted == [{"action": "reload", "request-id": 7}]
    assert polls[0] > 2
    assert polls[0] == pytest.approx(8.95)


def test_operation_deadline_is_not_reset(live_dev, checkout, monkeypatch):
    instance = record_for(live_dev, checkout)
    clock = [100.0]
    monkeypatch.setattr(live_dev.time, "monotonic", lambda: clock[0])
    monkeypatch.setattr(live_dev.time, "sleep", lambda seconds: clock.__setitem__(0, clock[0] + seconds))
    submitted = []
    budgets = []
    def rpc(selected, request, timeout):
        if request["action"] == "status":
            return {"next-request-id": 8}
        if request["action"] == "manual":
            submitted.append(request)
        else:
            assert request == {"action": "operation", "request-id": 8}
            budgets.append(timeout)
            clock[0] += min(3, timeout)
        return {"status": "pending", "request-id": 8, "action": "manual", "instance-id": instance["instance-id"]}
    monkeypatch.setattr(live_dev, "remote_request", rpc)
    with pytest.raises(live_dev.LiveDevError, match="operation-timeout"):
        live_dev._operate(instance, "manual", 10)
    assert len(submitted) == 1
    assert budgets and all(earlier > later for earlier, later in zip(budgets, budgets[1:]))
    assert clock[0] <= 110.000001


def test_operation_terminal_identity_is_verified(live_dev, checkout, monkeypatch):
    instance = record_for(live_dev, checkout)
    submitted = []
    def rpc(selected, request, timeout):
        if request["action"] == "status":
            return {"next-request-id": 9}
        if request["action"] == "reload":
            submitted.append(request)
            return {"status": "pending", "request-id": 9, "action": "reload", "instance-id": instance["instance-id"]}
        return {"status": "succeeded", "request-id": 9, "action": "reload", "instance-id": "foreign"}
    monkeypatch.setattr(live_dev, "remote_request", rpc)
    with pytest.raises(live_dev.LiveDevError, match="operation-unverified"):
        live_dev._operate(instance, "reload", 10)
    assert len(submitted) == 1


def child_record(live_dev, checkout, child):
    record = record_for(live_dev, checkout)
    record["pid"] = child.pid
    record["process-start"] = Path(f"/proc/{child.pid}/stat").read_text().rsplit(")", 1)[1].split()[19]
    record["executable"] = os.readlink(f"/proc/{child.pid}/exe")
    record["executable-identity"] = live_dev._executable_identity(Path(f"/proc/{child.pid}/exe"))
    return record


@pytest.mark.parametrize("restart", [False, True])
def test_prepublication_timeout_retry_never_launches_duplicate(live_dev, checkout, monkeypatch, restart):
    children = []
    recipe = {"executable": sys.executable, "argv": ["-c", "import sys; sys.stdin.buffer.read()"],
              "cwd": str(checkout), "environment": dict(os.environ, PRIVATE_RECIPE="never-persist")}
    def launch(root, saved):
        child = subprocess.Popen([saved["executable"], *saved["argv"]], stdin=subprocess.PIPE)
        children.append(child)
        return child
    monkeypatch.setattr(live_dev, "_default_recipe", lambda *a: recipe)
    monkeypatch.setattr(live_dev, "_launch", launch)
    try:
        with pytest.raises(live_dev.LiveDevError, match="startup-timeout"):
            if restart:
                old = dict(record_for(live_dev, checkout), **{"process-start": "0"})
                live_dev.restart_instance(checkout, old, recipe, timeout=0.1)
            else:
                live_dev.ensure_started(checkout, timeout=0.1)
        assert len(children) == 1 and children[0].poll() is None
        assert list(live_dev._registered_records(checkout)) == [], "child must still be prepublication"
        intent = live_dev._read_json(live_dev._partition(checkout) / "launch.json")
        assert intent["state"] == "spawned"
        owned = child_record(live_dev, checkout, children[0])
        assert all(intent["process"][key] == owned[key] for key in live_dev.PROCESS_IDENTITY if key != "instance-id")
        with pytest.raises(live_dev.LiveDevError):
            live_dev.ensure_started(checkout, timeout=0.1)
        assert len(children) == 1, "live prepublication child must block retry, not authorize a duplicate"
        for path in live_dev._partition(checkout).glob("*.json"):
            assert "never-persist" not in path.read_text()
            assert path.stat().st_mode & 0o777 == 0o600
        # Only confirmed exit of this exact owned child allows the next launch.
        children[0].communicate(b"x", timeout=5)
        with pytest.raises(live_dev.LiveDevError, match="startup-timeout"):
            live_dev.ensure_started(checkout, timeout=0.1)
        assert len(children) == 2
    finally:
        for child in children:
            if child.poll() is None:
                child.communicate(b"x", timeout=5)


def test_pending_launch_can_rejoin_verified_publication(live_dev, checkout, monkeypatch):
    child = subprocess.Popen([sys.executable, "-c", "import sys; sys.stdin.buffer.read()"], stdin=subprocess.PIPE)
    record = child_record(live_dev, checkout, child)
    path = live_dev._partition(checkout) / "launch.json"
    live_dev._write_json(path, {"schema-version": 1, "checkout-root": str(checkout), "state": "spawned",
                               "process": {key: record[key] for key in live_dev.PROCESS_IDENTITY}})
    publish(live_dev, checkout, record)
    monkeypatch.setattr(live_dev, "remote_request", lambda *args: record)
    monkeypatch.setattr(live_dev, "_launch", lambda *args: pytest.fail("published owned child duplicated"))
    try:
        assert live_dev.ensure_started(checkout) == record
        assert not path.exists()
    finally:
        child.communicate(b"x", timeout=5)


@pytest.mark.parametrize("kind", ["pending", "malformed", "image-mismatch"])
def test_uncertain_owned_launch_blocks_without_signaling(live_dev, checkout, monkeypatch, kind):
    record = record_for(live_dev, checkout)
    intent = {"schema-version": 1, "checkout-root": str(checkout), "state": "spawned",
              "process": {key: record[key] for key in live_dev.PROCESS_IDENTITY}}
    if kind == "pending":
        intent = {"schema-version": 1, "checkout-root": str(checkout), "state": "pending"}
    elif kind == "malformed":
        intent["process"]["boot-id"] = None
    else:
        intent["process"]["executable-identity"] = "0:0:0:0:0"
    path = live_dev._partition(checkout) / "launch.json"
    live_dev._write_json(path, intent)
    monkeypatch.setattr(live_dev, "_launch", lambda *args: pytest.fail("uncertain child duplicated"))
    monkeypatch.setattr(live_dev.signal, "pidfd_send_signal", lambda *args: pytest.fail("uncertain child signaled"))
    with pytest.raises(live_dev.LiveDevError):
        live_dev.ensure_started(checkout)
    assert live_dev._read_json(path) == intent


@pytest.mark.parametrize("version", [True, False, None, "1", {}, []])
def test_malformed_launch_schema_cannot_authorize_stale_cleanup(live_dev, checkout, monkeypatch, version):
    record = dict(record_for(live_dev, checkout), **{"process-start": "0"})
    intent = {"schema-version": version, "checkout-root": str(checkout), "state": "spawned",
              "process": {key: record[key] for key in live_dev.PROCESS_IDENTITY}}
    path = live_dev._partition(checkout) / "launch.json"
    live_dev._write_json(path, intent)
    monkeypatch.setattr(live_dev, "_default_recipe", lambda *args: pytest.fail("invalid launch metadata authorized a new recipe"))
    with pytest.raises(live_dev.LiveDevError, match="invalid-launch-record"):
        live_dev.ensure_started(checkout)
    assert live_dev._read_json(path) == intent


@pytest.mark.parametrize("exit_before_wait", [False, True])
def test_exited_owned_startup_releases_launch_blocker(live_dev, checkout, monkeypatch, exit_before_wait):
    recipe = {"executable": sys.executable}
    children = []
    def launch(*args):
        child = subprocess.Popen([sys.executable, "-c", "pass"])
        children.append(child)
        if exit_before_wait:
            child.wait(timeout=5)
        return child
    monkeypatch.setattr(live_dev, "_launch", launch)
    try:
        with pytest.raises(live_dev.LiveDevError, match="startup-exited"):
            live_dev._launch_and_wait(checkout, recipe, 1)
        assert not (live_dev._partition(checkout) / "launch.json").exists()
    finally:
        for child in children:
            child.wait(timeout=5)


def test_confirmed_popen_failure_releases_launch_intent(live_dev, checkout):
    recipe = {"executable": sys.executable, "argv": [], "environment": {}, "cwd": "/nonexistent-live-dev-cwd"}
    with pytest.raises(live_dev.LiveDevError, match="launch-failed"):
        live_dev._launch_and_wait(checkout, recipe, 1)
    assert not (live_dev._partition(checkout) / "launch.json").exists()


def test_saved_selection_app_exit_start_replaces_stale(live_dev, checkout, monkeypatch, capsys):
    child = subprocess.Popen([sys.executable, "-c", "import sys; sys.stdin.buffer.read(1)"], stdin=subprocess.PIPE)
    old = child_record(live_dev, checkout, child)
    publish(live_dev, checkout, old)
    live_dev._save_selection(checkout, old)
    child.communicate(b"x", timeout=5)
    new = dict(record_for(live_dev, checkout), **{"instance-id": "replacement"})
    launched = []
    monkeypatch.setattr(live_dev, "_default_recipe", lambda *a: {})
    def launch_and_wait(*args):
        launched.append(True)
        return new
    monkeypatch.setattr(live_dev, "_launch_and_wait", launch_and_wait)
    assert live_dev.main(["start", "--repo-root", str(checkout)]) == 0
    assert json.loads(capsys.readouterr().out)["instance-id"] == "replacement"
    assert live_dev._load_selection(checkout)["instance-id"] == "replacement"
    assert launched == [True]


def test_explicit_stale_selection_still_refuses_launch(live_dev, checkout, monkeypatch):
    monkeypatch.setattr(live_dev, "_launch", lambda *a: pytest.fail("explicit stale target launched"))
    with pytest.raises(live_dev.LiveDevError, match="stale-selection"):
        live_dev.ensure_started(checkout, selection="absent")


def test_saved_preference_stale_with_multiple_candidates_is_ambiguous(live_dev, checkout, monkeypatch):
    saved = dict(record_for(live_dev, checkout), **{"instance-id": "expired", "process-start": "0"})
    candidates = [dict(saved, **{"instance-id": name}) for name in ("a", "b")]
    monkeypatch.setattr(live_dev, "discover", lambda *a, **k: candidates)
    with pytest.raises(live_dev.LiveDevError, match="ambiguous-instance"):
        live_dev.ensure_started(checkout, saved_selection=saved)


@pytest.mark.parametrize("boot", [None, True, False, {}, [], "old", "", 123])
def test_malformed_boot_record_blocks_and_is_retained(live_dev, checkout, monkeypatch, boot):
    record = record_for(live_dev, checkout)
    record["boot-id"] = boot
    path = publish(live_dev, checkout, record)
    monkeypatch.setattr(live_dev, "_launch", lambda *a: pytest.fail("malformed identity permitted launch"))
    with pytest.raises(live_dev.LiveDevError, match="invalid-record"):
        live_dev.ensure_started(checkout)
    assert path.exists()


@pytest.mark.parametrize("recovery", [False, True])
def test_restart_preserves_other_healthy_instance(live_dev, checkout, monkeypatch, recovery):
    selected = record_for(live_dev, checkout)
    other = dict(selected, **{"instance-id": "other"})
    replacement = dict(selected, **{"instance-id": "replacement"})
    records = {record["instance-id"]: record for record in (selected, other)}
    selected_path = publish(live_dev, checkout, selected)
    publish(live_dev, checkout, other)
    stopped = []
    def stop(instance, timeout):
        stopped.append(instance["instance-id"])
        selected_path.unlink()
    def launch_and_wait(*args):
        records[replacement["instance-id"]] = replacement
        publish(live_dev, checkout, replacement)
        return replacement
    monkeypatch.setattr(live_dev, "_stop_instance", stop)
    monkeypatch.setattr(live_dev, "remote_request", lambda instance, *a: dict(records[instance["instance-id"]]))
    monkeypatch.setattr(live_dev, "_launch_and_wait", launch_and_wait)
    if recovery:
        monkeypatch.setattr(live_dev, "_recipe", lambda *a: {})
        monkeypatch.setattr(live_dev, "_operate", lambda *a: {"status": "failed", "recovery-required": True})
        result, code = live_dev._reload(checkout, selected, 1)
        assert code == 1 and result["recovery"]["instance-id"] == replacement["instance-id"]
    else:
        assert live_dev.restart_instance(checkout, selected, {}) == replacement
    assert stopped == [selected["instance-id"]]
    assert live_dev._load_selection(checkout)["instance-id"] == replacement["instance-id"]


@pytest.mark.parametrize("changed,value", [("action", "manual"), ("request-id", 2), ("request-id", True)])
def test_operation_shared_id_conflict_never_succeeds_or_recovers(live_dev, checkout, monkeypatch, changed, value):
    instance = record_for(live_dev, checkout)
    monkeypatch.setattr(live_dev, "_recipe", lambda *a: {})
    monkeypatch.setattr(live_dev, "restart_instance", lambda *a, **k: pytest.fail("dedup conflict authorized recovery"))
    submitted = []
    def rpc(selected, request, timeout):
        if request["action"] == "status":
            return {"next-request-id": 1}
        submitted.append(request)
        result = {"status": "succeeded", "request-id": 1, "action": "reload", "instance-id": instance["instance-id"]}
        result[changed] = value
        return result
    monkeypatch.setattr(live_dev, "remote_request", rpc)
    result, exit_code = live_dev._reload(checkout, instance, 1)
    assert exit_code == 1
    assert result["reload"]["error"] == "operation-conflict"
    assert "recovery" not in result
    assert len(submitted) == 1


def test_concurrent_mutation_id_allocation_is_serialized(live_dev, checkout, monkeypatch):
    instance = record_for(live_dev, checkout)
    entered = threading.Event()
    release = threading.Event()
    second_entered = threading.Event()
    state = {"statuses": 0, "next": 1}
    def rpc(selected, request, timeout):
        if request["action"] == "status":
            state["statuses"] += 1
            if state["statuses"] == 1:
                entered.set()
                assert release.wait(3)
            else:
                second_entered.set()
            return {"next-request-id": state["next"]}
        state["next"] += 1
        return {"status": "succeeded", **request, "instance-id": instance["instance-id"]}
    monkeypatch.setattr(live_dev, "remote_request", rpc)
    with ThreadPoolExecutor(max_workers=2) as pool:
        first = pool.submit(live_dev._operate, instance, "manual", 3)
        assert entered.wait(2)
        second = pool.submit(live_dev._operate, instance, "reload", 3)
        overlapping = second_entered.wait(0.1)
        release.set()
        results = [first.result(timeout=5), second.result(timeout=5)]
    assert not overlapping
    assert [result["request-id"] for result in results] == [1, 2]


@pytest.mark.parametrize("phase", ["acquire", "escalate"])
def test_changed_kernel_image_is_never_signaled(live_dev, checkout, monkeypatch, phase):
    code = "import os,sys; sys.stdin.buffer.read(1); os.execv('/bin/sh',['sh','-c','read line'])"
    child = subprocess.Popen([sys.executable, "-c", code], stdin=subprocess.PIPE)
    record = child_record(live_dev, checkout, child)
    def change_image():
        child.stdin.write(b"x")
        child.stdin.flush()
        deadline = time.monotonic() + 3
        while os.readlink(f"/proc/{child.pid}/exe") == record["executable"]:
            assert time.monotonic() < deadline
            time.sleep(0.01)
    monkeypatch.setattr(live_dev.signal, "pidfd_send_signal", lambda *a: pytest.fail("changed executable signaled"))
    try:
        if phase == "acquire":
            change_image()
            with pytest.raises(live_dev.LiveDevError, match="unavailable"):
                with live_dev._verified_pidfd(record):
                    pytest.fail("changed image accepted")
        else:
            with live_dev._verified_pidfd(record) as fd:
                change_image()
                with pytest.raises(live_dev.LiveDevError, match="unavailable"):
                    live_dev._await_exit(record, fd, 0.01)
    finally:
        child.communicate(b"\n", timeout=5)


def test_unlinked_old_executable_requires_matching_kernel_stat(live_dev, checkout, monkeypatch):
    record = record_for(live_dev, checkout)
    original = os.readlink
    monkeypatch.setattr(live_dev.os, "readlink", lambda path: original(path) + " (deleted)")
    live_dev._check_process(record)


def test_operation_status_exhaustion_prevents_submission(live_dev, checkout, monkeypatch):
    instance = record_for(live_dev, checkout)
    clock = [0.0]
    monkeypatch.setattr(live_dev.time, "monotonic", lambda: clock[0])
    calls = []
    def rpc(selected, request, timeout):
        calls.append(request["action"])
        clock[0] = 2
        return {"next-request-id": 1, "status": "succeeded", "request-id": 1,
                "action": "reload", "instance-id": instance["instance-id"]}
    monkeypatch.setattr(live_dev, "remote_request", rpc)
    with pytest.raises(live_dev.LiveDevError, match="operation-timeout"):
        live_dev._operate(instance, "reload", 1)
    assert calls == ["status"]


def test_operation_submission_uses_only_remainder(live_dev, checkout, monkeypatch):
    instance = record_for(live_dev, checkout)
    clock = [0.0]
    monkeypatch.setattr(live_dev.time, "monotonic", lambda: clock[0])
    def rpc(selected, request, timeout):
        if request["action"] == "status":
            clock[0] = 0.75
            return {"next-request-id": 1}
        assert timeout <= 0.25
        return {"status": "succeeded", "request-id": 1, "action": "manual", "instance-id": instance["instance-id"]}
    monkeypatch.setattr(live_dev, "remote_request", rpc)
    assert live_dev._operate(instance, "manual", 1)["status"] == "succeeded"


def test_operation_late_terminal_is_not_success(live_dev, checkout, monkeypatch):
    instance = record_for(live_dev, checkout)
    clock = [0.0]
    monkeypatch.setattr(live_dev.time, "monotonic", lambda: clock[0])
    def rpc(selected, request, timeout):
        if request["action"] == "status":
            return {"next-request-id": 1}
        clock[0] = 2
        return {"status": "succeeded", "request-id": 1, "action": "reload", "instance-id": instance["instance-id"]}
    monkeypatch.setattr(live_dev, "remote_request", rpc)
    with pytest.raises(live_dev.LiveDevError, match="operation-timeout"):
        live_dev._operate(instance, "reload", 1)


def spawn_observer_module():
    path = Path(__file__).parents[2] / "tests/live_dev_spawn_observer.py"
    assert path.exists(), "fixture must own actual app spawn before publication"
    spec = importlib.util.spec_from_file_location("live_dev_spawn_observer", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_prepublication_hang_has_owned_provenance_and_cleanup(live_dev, checkout):
    observer = spawn_observer_module()
    fixture = cleanup_fixture(live_dev, checkout)
    recipe = {"executable": sys.executable, "argv": ["-c", "import sys; sys.stdin.buffer.read()"],
              "cwd": str(checkout), "environment": dict(os.environ)}
    def launch(root, saved):
        pending = list((fixture.observer_root / "launches").glob("*.json"))
        assert len(pending) == 1
        assert live_dev._read_json(pending[0])["state"] == "pending"
        return subprocess.Popen([saved["executable"], *saved["argv"]], stdin=subprocess.PIPE,
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    child = observer.observe_launch(live_dev, launch, fixture.observer_root, checkout, recipe)
    try:
        assert child.poll() is None
        assert not list((fixture.base / "runtime/space-live-dev").glob("*/instances/*.json"))
        fixture.collect_app_spawns()
        assert len(fixture.app_spawns) == 1
        receipt = next(iter(fixture.app_spawns.values()))
        assert receipt["record"]["pid"] == child.pid
        assert receipt["pidfd"] is not None
        persisted = live_dev._read_json(next((fixture.observer_root / "launches").glob("*.json")))
        assert persisted["record"] == receipt["record"]
        assert "argv" not in persisted["record"] and "environment" not in persisted["record"]
        fixture.cleanup()
        child.wait(timeout=5)
        assert child.returncode is not None
    finally:
        # Test failure path uses this known direct child's input, never a guessed PID.
        if child.poll() is None:
            child.communicate(b"x", timeout=5)
        if fixture.observer_socket.fileno() != -1:
            fixture.cleanup()


def test_unaccounted_spawn_fails_cleanup_and_keeps_provenance(live_dev, checkout):
    fixture = cleanup_fixture(live_dev, checkout)
    observer_root = fixture.base / "observer"
    launches = observer_root / "launches"
    launches.mkdir(parents=True, mode=0o700, exist_ok=True)
    intent = launches / ("1" * 32 + ".json")
    live_dev._write_json(intent, {"launch-id": "1" * 32, "checkout-root": str(checkout), "state": "pending"})
    fixture.observer_root = observer_root
    with pytest.raises(AssertionError, match="unaccounted launch"):
        fixture.cleanup()
    assert intent.exists()


def test_restart_quit_uses_existing_mutation_lock(live_dev, checkout, monkeypatch):
    instance = record_for(live_dev, checkout)
    calls = []
    def rpc(selected, request, timeout):
        with pytest.raises(live_dev.LiveDevError, match="lock-timeout"):
            with live_dev._checkout_lock(checkout, 0.001):
                pytest.fail("quit allocation was not serialized")
        calls.append(request["action"])
        if request["action"] == "status":
            return {"next-request-id": 3}
        return {"status": "pending", "action": "quit", "request-id": 3, "instance-id": instance["instance-id"]}
    monkeypatch.setattr(live_dev, "remote_request", rpc)
    monkeypatch.setattr(live_dev, "_await_exit", lambda *a: None)
    with live_dev._checkout_lock(checkout, 1):
        live_dev._stop_instance(instance, 1)
    assert calls == ["status", "quit"]


@pytest.mark.parametrize("target_exits", [False, True])
def test_unverified_reload_recovers_unavailable_target_with_peer(live_dev, checkout, monkeypatch, target_exits):
    child = subprocess.Popen([sys.executable, "-c", "import sys; sys.stdin.buffer.read(1)"], stdin=subprocess.PIPE)
    selected = dict(child_record(live_dev, checkout, child), **{"instance-id": "selected"})
    peer = dict(record_for(live_dev, checkout), **{"instance-id": "peer"})
    records = {selected["instance-id"]: selected, peer["instance-id"]: peer}
    for record in records.values():
        publish(live_dev, checkout, record)
    state = {"unavailable": False, "launches": 0, "awaited": 0}
    children = [child]
    recipe = {"executable": selected["executable"], "argv": [], "cwd": str(checkout),
              "environment": {"TOKEN": "private"}}
    def rpc(instance, request, timeout):
        if request["action"] == "launch-recipe":
            assert not state["unavailable"]
            return recipe
        if instance["instance-id"] == selected["instance-id"] and state["unavailable"]:
            raise live_dev.LiveDevError("remote-timeout")
        return dict(records[instance["instance-id"]])
    def unverified(*args):
        state["unavailable"] = True
        if target_exits:
            child.communicate(b"x", timeout=5)
        raise live_dev.LiveDevError("remote-timeout", **{"mutation-submitted": True})
    def await_exit(instance, fd, timeout):
        assert instance["instance-id"] == selected["instance-id"] and fd is not None
        live_dev._check_process(instance)
        state["awaited"] += 1
        child.communicate(b"x", timeout=5)
    def launch(root, saved):
        assert saved == recipe
        state["launches"] += 1
        replacement_child = subprocess.Popen([sys.executable, "-c", "import sys; sys.stdin.buffer.read(1)"], stdin=subprocess.PIPE)
        children.append(replacement_child)
        replacement = dict(child_record(live_dev, checkout, replacement_child), **{"instance-id": "replacement"})
        records[replacement["instance-id"]] = replacement
        publish(live_dev, checkout, replacement)
        return replacement_child
    monkeypatch.setattr(live_dev, "remote_request", rpc)
    monkeypatch.setattr(live_dev, "_operate", unverified)
    monkeypatch.setattr(live_dev, "_await_exit", await_exit)
    monkeypatch.setattr(live_dev, "_launch", launch)
    try:
        result, code = live_dev._reload(checkout, selected, 1)
        assert code == 1 and result["reload"]["status"] == "unverified"
        assert result["recovery"] == {"status": "succeeded", "instance-id": "replacement"}
        assert state["launches"] == 1 and state["awaited"] == int(not target_exits)
        assert live_dev.verify_instance(peer, checkout) == peer
        assert "TOKEN" not in json.dumps(result)
    finally:
        for owned in children:
            if owned.poll() is None:
                owned.communicate(b"x", timeout=5)


def test_restart_unavailable_unrelated_peer_remains_blocker(live_dev, checkout, monkeypatch):
    selected = dict(record_for(live_dev, checkout), **{"instance-id": "selected"})
    peer = dict(selected, **{"instance-id": "peer"})
    paths = [publish(live_dev, checkout, record) for record in (selected, peer)]
    def rpc(*args):
        raise live_dev.LiveDevError("remote-timeout")
    monkeypatch.setattr(live_dev, "remote_request", rpc)
    monkeypatch.setattr(live_dev, "_stop_instance", lambda *a: pytest.fail("uncertain peer permitted stop"))
    monkeypatch.setattr(live_dev, "_launch", lambda *a: pytest.fail("uncertain peer permitted launch"))
    with pytest.raises(live_dev.LiveDevError, match="unavailable"):
        live_dev.restart_instance(checkout, selected, {})
    assert all(path.exists() for path in paths)


def test_concurrent_same_target_restart_launches_one_replacement(live_dev, checkout, monkeypatch):
    child = subprocess.Popen([sys.executable, "-c", "import sys; sys.stdin.buffer.read(1)"], stdin=subprocess.PIPE)
    selected = dict(child_record(live_dev, checkout, child), **{"instance-id": "selected"})
    peer = dict(record_for(live_dev, checkout), **{"instance-id": "peer"})
    records = {selected["instance-id"]: selected, peer["instance-id"]: peer}
    for record in records.values():
        publish(live_dev, checkout, record)
    barrier = threading.Barrier(2)
    original_lock = live_dev._checkout_lock
    children = [child]
    launched = []
    @contextmanager
    def coordinated_lock(root, timeout):
        barrier.wait(timeout=3)
        with original_lock(root, timeout):
            yield
    def stop(instance, timeout):
        assert instance["instance-id"] == selected["instance-id"]
        if child.poll() is None:
            child.communicate(b"x", timeout=5)
    def launch(root, recipe):
        replacement_child = subprocess.Popen([sys.executable, "-c", "import sys; sys.stdin.buffer.read(1)"], stdin=subprocess.PIPE)
        children.append(replacement_child)
        instance_id = "replacement-" + str(len(launched) + 1)
        launched.append(instance_id)
        replacement = dict(child_record(live_dev, checkout, replacement_child), **{"instance-id": instance_id})
        records[instance_id] = replacement
        publish(live_dev, checkout, replacement)
        return replacement_child
    def attempt():
        try:
            return live_dev.restart_instance(checkout, selected, {"executable": sys.executable}, timeout=3)
        except live_dev.LiveDevError as error:
            return error.code
    monkeypatch.setattr(live_dev, "_checkout_lock", coordinated_lock)
    monkeypatch.setattr(live_dev, "remote_request", lambda instance, *a: dict(records[instance["instance-id"]]))
    monkeypatch.setattr(live_dev, "_stop_instance", stop)
    monkeypatch.setattr(live_dev, "_launch", launch)
    try:
        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(lambda _index: attempt(), range(2)))
        assert launched == ["replacement-1"]
        assert sum(isinstance(result, dict) for result in results) == 1
        assert any(result in ("replacement-conflict", "stale-restart-target") for result in results if isinstance(result, str))
        assert {record["instance-id"] for record in live_dev.discover(checkout)} == {"peer", "replacement-1"}
    finally:
        for owned in children:
            if owned.poll() is None:
                owned.communicate(b"x", timeout=5)


def test_restart_rejects_new_peer_arriving_while_waiting(live_dev, checkout, monkeypatch):
    selected = dict(record_for(live_dev, checkout), **{"instance-id": "selected"})
    peer = dict(selected, **{"instance-id": "peer"})
    newcomer = dict(selected, **{"instance-id": "newcomer"})
    records = {record["instance-id"]: record for record in (selected, peer, newcomer)}
    for record in (selected, peer):
        publish(live_dev, checkout, record)
    original_lock = live_dev._checkout_lock
    @contextmanager
    def changed_cohort(root, timeout):
        publish(live_dev, checkout, newcomer)
        with original_lock(root, timeout):
            yield
    monkeypatch.setattr(live_dev, "_checkout_lock", changed_cohort)
    monkeypatch.setattr(live_dev, "remote_request", lambda instance, *a: dict(records[instance["instance-id"]]))
    monkeypatch.setattr(live_dev, "_stop_instance", lambda *a: pytest.fail("new peer adopted before stop"))
    monkeypatch.setattr(live_dev, "_launch", lambda *a: pytest.fail("new peer authorized launch"))
    with pytest.raises(live_dev.LiveDevError, match="replacement-conflict"):
        live_dev.restart_instance(checkout, selected, {})


def test_restart_stale_target_cannot_authorize_existing_replacement(live_dev, checkout, monkeypatch):
    selected = dict(record_for(live_dev, checkout), **{"instance-id": "selected", "process-start": "0"})
    replacement = dict(record_for(live_dev, checkout), **{"instance-id": "replacement"})
    publish(live_dev, checkout, replacement)
    monkeypatch.setattr(live_dev, "remote_request", lambda *a: dict(replacement))
    monkeypatch.setattr(live_dev, "_stop_instance", lambda *a: pytest.fail("stale target adopted replacement"))
    monkeypatch.setattr(live_dev, "_launch", lambda *a: pytest.fail("duplicate replacement"))
    with pytest.raises(live_dev.LiveDevError, match="stale-restart-target"):
        live_dev.restart_instance(checkout, selected, {})
    assert live_dev.discover(checkout) == [replacement]


def test_restart_kernel_only_target_still_requires_exact_metadata(live_dev, checkout, monkeypatch):
    selected = record_for(live_dev, checkout)
    changed = dict(selected, endpoint=selected["endpoint"] + "-changed")
    path = publish(live_dev, checkout, changed)
    monkeypatch.setattr(live_dev, "remote_request", lambda *a: pytest.fail("mismatched target reached RPC"))
    monkeypatch.setattr(live_dev, "_stop_instance", lambda *a: pytest.fail("mismatched target signaled"))
    with pytest.raises(live_dev.LiveDevError, match="replacement-conflict"):
        live_dev.restart_instance(checkout, selected, {})
    assert path.exists()


def test_cli_restart_keeps_verified_peer_authorization_if_target_exits_after_recipe(live_dev, checkout, monkeypatch, capsys):
    child = subprocess.Popen([sys.executable, "-c", "import sys; sys.stdin.buffer.read(1)"], stdin=subprocess.PIPE)
    selected = dict(child_record(live_dev, checkout, child), **{"instance-id": "selected"})
    peer = dict(record_for(live_dev, checkout), **{"instance-id": "peer"})
    records = {record["instance-id"]: record for record in (selected, peer)}
    for record in records.values():
        publish(live_dev, checkout, record)
    recipe = {"executable": selected["executable"], "argv": [], "cwd": str(checkout), "environment": {}}
    children = [child]
    def rpc(instance, request, timeout):
        if request["action"] == "launch-recipe":
            child.communicate(b"x", timeout=5)
            return recipe
        return dict(records[instance["instance-id"]])
    def launch(root, saved):
        assert saved == recipe
        replacement_child = subprocess.Popen([sys.executable, "-c", "import sys; sys.stdin.buffer.read(1)"], stdin=subprocess.PIPE)
        children.append(replacement_child)
        replacement = dict(child_record(live_dev, checkout, replacement_child), **{"instance-id": "replacement"})
        records[replacement["instance-id"]] = replacement
        publish(live_dev, checkout, replacement)
        return replacement_child
    monkeypatch.setattr(live_dev, "remote_request", rpc)
    monkeypatch.setattr(live_dev, "_launch", launch)
    try:
        assert live_dev.main(["restart", "--repo-root", str(checkout), "--instance", "selected"]) == 0
        assert json.loads(capsys.readouterr().out)["instance-id"] == "replacement"
        assert live_dev.verify_instance(peer, checkout) == peer
    finally:
        for owned in children:
            if owned.poll() is None:
                owned.communicate(b"x", timeout=5)
