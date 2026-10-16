#!/usr/bin/env python3
"""Verified, checkout-scoped Linux app lifecycle. No process/legacy scanning.

Only public identity is persisted. Launch recipes stay in memory and are never
included in diagnostics, subprocess errors, or command output.
"""
import argparse
from contextlib import contextmanager
import fcntl
import json
import math
import os
from pathlib import Path
import re
import select
import signal
import stat
import subprocess
import time
import uuid


class LiveDevError(Exception):
    def __init__(self, code, **details):
        self.code = code
        self.details = details
        super().__init__(code)


IDENTITY = ("instance-id", "checkout-root", "source-root", "main-source", "pid", "uid",
            "boot-id", "process-start", "executable", "executable-identity",
            "native-source-root", "native-build-root", "build-profile", "cef-enabled", "endpoint")
PUBLIC = IDENTITY + ("schema-version", "ready", "faulted", "mode", "generation",
                     "next-request-id", "capabilities", "error")
PROCESS_IDENTITY = ("instance-id", "checkout-root", "pid", "uid", "boot-id", "process-start",
                    "executable", "executable-identity")


def _public(record):
    return {key: record[key] for key in PUBLIC if key in record}


def canonical_checkout(path):
    try:
        result = subprocess.run(["git", "-C", str(Path(path).resolve()), "rev-parse", "--show-toplevel"],
                                capture_output=True, text=True, timeout=10, check=True)
        return Path(result.stdout.strip()).resolve(strict=True)
    except (OSError, ValueError, subprocess.SubprocessError):
        raise LiveDevError("not-a-checkout") from None


def _no_symlinks(path):
    if not path.is_absolute():
        raise LiveDevError("unsafe-runtime-path")
    for parent in (*reversed(path.parents), path):
        if parent.is_symlink():
            raise LiveDevError("unsafe-runtime-path")


def _private_directory(path, create=True):
    _no_symlinks(path)
    if create:
        path.mkdir(mode=0o700, exist_ok=True)
    info = path.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o700:
        raise LiveDevError("unsafe-runtime-directory")
    return path


def runtime_directory(env):
    xdg = env.get("XDG_RUNTIME_DIR")
    if xdg:
        root = _private_directory(Path(xdg), create=False)
        base = root / "space-live-dev"
        if len(str(base).encode()) < 70:
            return _private_directory(base)
    return _private_directory(Path(f"/tmp/space-live-dev-{os.getuid()}"))


def _partition(root):
    key = str(uuid.uuid5(uuid.NAMESPACE_URL, "space-live-dev:" + str(root)))
    return _private_directory(runtime_directory(os.environ) / key)


@contextmanager
def _owned_file(path, flags):
    fd = os.open(path, flags | os.O_NOFOLLOW | os.O_CLOEXEC | os.O_NONBLOCK, 0o600)
    try:
        info = os.fstat(fd)
        if (not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid()
                or stat.S_IMODE(info.st_mode) != 0o600 or info.st_nlink != 1):
            raise LiveDevError("unsafe-private-file")
        yield fd
    finally:
        os.close(fd)


def _read_json(path):
    with _owned_file(path, os.O_RDONLY) as fd:
        with os.fdopen(os.dup(fd)) as stream:
            return json.load(stream)


def _write_json(path, value):
    temporary = path.with_suffix(".tmp")
    with _owned_file(temporary, os.O_WRONLY | os.O_CREAT) as fd:
        os.ftruncate(fd, 0)
        os.write(fd, json.dumps(value).encode())
        os.fsync(fd)
    os.replace(temporary, path)


def _identity_numbers(record):
    if not isinstance(record, dict):
        raise LiveDevError("invalid-record")
    normalized = dict(record)
    for key, minimum, maximum in (("pid", 1, 2147483647), ("uid", 0, 4294967294)):
        value = record.get(key)
        if (type(value) not in (int, float)
                or (type(value) is float and (not math.isfinite(value) or not value.is_integer()))
                or not minimum <= value <= maximum):
            raise LiveDevError("invalid-record")
        normalized[key] = int(value)
    return normalized


def _validate_process_identity(record, root):
    record = _identity_numbers(record)
    if any(key not in record for key in PROCESS_IDENTITY):
        raise LiveDevError("invalid-record")
    if (not isinstance(record["instance-id"], str)
            or not re.fullmatch(r"[A-Za-z0-9-]{1,64}", record["instance-id"])
            or record["checkout-root"] != str(root) or record["uid"] != os.getuid()
            or not isinstance(record["process-start"], str)
            or not re.fullmatch(r"0|[1-9][0-9]{0,19}", record["process-start"])
            or int(record["process-start"]) > 18446744073709551615):
        raise LiveDevError("invalid-record")
    boot = record["boot-id"]
    try:
        if not isinstance(boot, str) or str(uuid.UUID(boot)) != boot:
            raise ValueError()
    except ValueError:
        raise LiveDevError("invalid-record") from None
    executable_identity = record["executable-identity"]
    if (not isinstance(executable_identity, str)
            or not re.fullmatch(r"[0-9]+:[0-9]+:[0-9]+:-?[0-9]+:[0-9]{1,9}", executable_identity)
            or int(executable_identity.rsplit(":", 1)[1]) >= 1000000000
            or not isinstance(record["executable"], str) or not Path(record["executable"]).is_absolute()):
        raise LiveDevError("invalid-record")
    return record


def _validate_identity(record, root):
    record = _validate_process_identity(record, root)
    if (any(key not in record for key in IDENTITY)
            or not isinstance(record["build-profile"], str) or not record["build-profile"]
            or type(record["cef-enabled"]) is not bool):
        raise LiveDevError("invalid-record")
    for key in ("source-root", "main-source", "executable", "native-source-root", "native-build-root"):
        if not isinstance(record[key], str) or not Path(record[key]).is_absolute():
            raise LiveDevError("invalid-record")
    source = Path(record["source-root"])
    if (not source.is_relative_to(root) or Path(record["main-source"]) != source / "main.fnl"
            or source.resolve() != source):
        raise LiveDevError("invalid-record")
    if record["endpoint"] is not False and (not isinstance(record["endpoint"], str) or not record["endpoint"]):
        raise LiveDevError("invalid-record")
    return record


def _validate_record(record, root):
    if (not isinstance(record, dict) or type(record.get("schema-version")) not in (int, float)
            or record["schema-version"] != 1):
        raise LiveDevError("invalid-record")
    return _validate_identity(record, root)


def _executable_identity(path):
    info = path.stat()
    return f"{info.st_dev}:{info.st_ino}:{info.st_size}:{info.st_mtime_ns // 1000000000}:{info.st_mtime_ns % 1000000000}"


def _check_process(record):
    """Only a registered PID's public kernel identity; never argv/environ."""
    record = _identity_numbers(record)
    try:
        boot = Path("/proc/sys/kernel/random/boot_id").read_text().strip()
    except OSError:
        raise LiveDevError("unavailable", **{"instance-id": record["instance-id"]}) from None
    try:
        proc = Path("/proc") / str(record["pid"])
        fields = (proc / "stat").read_text().rsplit(")", 1)[1].split()
        if boot != record["boot-id"] or fields[19] != record["process-start"] or fields[0] == "Z":
            raise LiveDevError("stale-instance")
        if proc.stat().st_uid != record["uid"]:
            raise LiveDevError("unavailable", **{"instance-id": record["instance-id"]})
        # Linux preserves the old inode through /proc even after an executable
        # is unlinked/replaced. A deleted suffix alone never authorizes signals.
        kernel_executable = os.readlink(proc / "exe").removesuffix(" (deleted)")
        if (kernel_executable != record["executable"]
                or _executable_identity(proc / "exe") != record["executable-identity"]):
            raise LiveDevError("unavailable", **{"instance-id": record["instance-id"]})
    except (FileNotFoundError, ProcessLookupError):
        raise LiveDevError("stale-instance") from None
    except (OSError, IndexError, ValueError):
        raise LiveDevError("unavailable", **{"instance-id": record["instance-id"]}) from None


def verify_instance(record, repo_root, timeout=2):
    root = canonical_checkout(repo_root)
    record = _validate_record(record, root)
    _check_process(record)
    try:
        if not record["endpoint"]:
            raise LiveDevError("no-transport")
        reply = remote_request(record, {"action": "status"}, timeout)
        reply = _validate_record(reply, root)
        if any(reply.get(key) != record[key] for key in IDENTITY):
            raise LiveDevError("identity-mismatch")
        _check_process(record)
        return _public(reply)
    except LiveDevError:
        raise LiveDevError("unavailable", **{"instance-id": record["instance-id"]}) from None


def _remove_stale(path, record):
    # Never unlink explicit external endpoints, non-sockets, or foreign paths.
    endpoint = record["endpoint"]
    base = runtime_directory(os.environ)
    if isinstance(endpoint, str) and endpoint.startswith("ipc://"):
        socket = Path(endpoint[6:])
        if socket.parent == base and re.fullmatch(r"s-[A-Za-z0-9-]+", socket.name):
            try:
                info = socket.lstat()
                if stat.S_ISSOCK(info.st_mode) and info.st_uid == os.getuid():
                    socket.unlink()
            except FileNotFoundError:
                pass
    path.unlink(missing_ok=True)


def _registered_records(root):
    directory = _private_directory(_partition(root) / "instances")
    for path in sorted(directory.glob("*.json")):
        try:
            record = _read_json(path)
            record = _validate_record(record, root)
            if path.name != record["instance-id"] + ".json":
                raise LiveDevError("invalid-record")
        except FileNotFoundError:
            # Atomic unpublication while discovering is harmless, unlike timeout.
            continue
        except (OSError, ValueError, TypeError, KeyError):
            raise LiveDevError("invalid-record", record=path.name) from None
        yield path, record


def discover(repo_root, timeout=2):
    root = canonical_checkout(repo_root)
    instances = []
    for path, record in _registered_records(root):
        try:
            instances.append(verify_instance(record, root, timeout))
        except LiveDevError as error:
            if error.code != "stale-instance":
                raise
            _remove_stale(path, record)
    return instances


def choose_instance(instances, selection):
    if selection is not None:
        for record in instances:
            if isinstance(selection, str):
                matches = record["instance-id"] == selection
            else:
                matches = all(record.get(key) == selection.get(key) for key in IDENTITY if key in selection)
            if matches:
                return record
        raise LiveDevError("stale-selection")
    if len(instances) > 1:
        raise LiveDevError("ambiguous-instance", candidates=[_public(record) for record in instances])
    if not instances:
        raise LiveDevError("no-instance")
    return instances[0]


def _save_selection(root, record):
    _write_json(_partition(root) / "selection.json", {key: record[key] for key in IDENTITY})


def _load_selection(root):
    try:
        selection = _read_json(_partition(root) / "selection.json")
        if not isinstance(selection, dict) or set(selection) != set(IDENTITY):
            raise LiveDevError("invalid-selection")
        return _validate_identity(selection, root)
    except FileNotFoundError:
        return None
    except (OSError, ValueError):
        raise LiveDevError("invalid-selection") from None


def _fennel_string(value: str) -> str:
    return '"' + ''.join(f'\\{byte:03d}' for byte in value.encode('utf-8')) + '"'


def _client_env(instance):
    env = dict(os.environ)
    source = Path(instance["source-root"])
    paths = str(source / "?.fnl") + ";" + str(source / "?/init.fnl")
    env.update(FENNEL_PATH=paths, FENNEL_MACRO_PATH=paths,
               SPACE_ASSETS_PATH=str(source.parent) + os.pathsep + str(Path(instance["native-source-root"]) / "assets"),
               SPACE_LOG_DIR=str(_private_directory(_partition(Path(instance["checkout-root"])) / "logs")))
    return env


def _remote_code(instance, code, timeout):
    args = [instance["executable"], "-m", "tools.remote-control-client:main", "--",
            "--endpoint", instance["endpoint"], "--timeout-ms", str(max(1, int(timeout * 1000))), "-c", code]
    try:
        result = subprocess.run(args, cwd=instance["native-build-root"], env=_client_env(instance),
                                stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=timeout + 1)
    except subprocess.TimeoutExpired:
        raise LiveDevError("remote-timeout") from None
    except OSError:
        raise LiveDevError("remote-failed") from None
    # Never include stdout/stderr: even a zero-exit error can contain a recipe.
    if result.returncode != 0:
        raise LiveDevError("remote-failed")
    text = result.stdout.strip()
    if text.startswith("error "):
        raise LiveDevError("remote-error")
    if not text.startswith("ok "):
        raise LiveDevError("remote-protocol")
    try:
        return json.loads(text[3:])
    except ValueError:
        raise LiveDevError("remote-protocol") from None


def remote_request(instance, request, timeout):
    request = dict(request, **{"expected-instance-id": instance["instance-id"]})
    encoded = _fennel_string(json.dumps(request, ensure_ascii=False))
    code = ("(do (local json (require :json)) (local live (require :live-dev-runtime)) "
            f"(json.dumps (live.rpc (json.loads {encoded}))))")
    return _remote_code(instance, code, timeout)


@contextmanager
def _checkout_lock(root, timeout):
    with _owned_file(_partition(root) / "launch.lock", os.O_CREAT | os.O_RDWR) as fd:
        deadline = time.monotonic() + timeout
        while True:
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    raise LiveDevError("lock-timeout") from None
                time.sleep(0.02)
        try:
            yield
        finally:
            fcntl.flock(fd, fcntl.LOCK_UN)


def _cache(build):
    try:
        return dict(line.split("=", 1) for line in (build / "CMakeCache.txt").read_text().splitlines()
                    if "=" in line and not line.startswith(("#", "//")))
    except OSError:
        raise LiveDevError("missing-build-cache") from None


def _build(args, cwd):
    logs = _private_directory(_partition(cwd) / "logs")
    with _owned_file(logs / "build.log", os.O_WRONLY | os.O_CREAT | os.O_APPEND) as fd:
        try:
            subprocess.run(args, cwd=cwd, stdin=subprocess.DEVNULL, stdout=fd, stderr=fd,
                           check=True, timeout=14400)
        except subprocess.TimeoutExpired:
            raise LiveDevError("build-timeout") from None
        except (OSError, subprocess.CalledProcessError):
            raise LiveDevError("build-failed") from None


def _build_command(build):
    jobs = os.environ.get("BUILD_JOBS", "1")
    if not jobs.isdigit() or int(jobs) < 1:
        raise LiveDevError("invalid-build-jobs")
    return ["cmake", "--build", str(build), "--parallel", jobs]


def _default_recipe(root):
    build = root / "build"
    executable = build / "space"
    if not executable.exists():
        if not (build / "CMakeCache.txt").exists():
            _build(["cmake", "-S", str(root), "-B", str(build), "-DCMAKE_BUILD_TYPE=Release",
                    "-DSPACE_BUILD_PROFILE=minimal", "-DSPACE_ENABLE_CEF=OFF"], root)
        else:
            cache = _cache(build)
            if Path(cache.get("CMAKE_HOME_DIRECTORY:INTERNAL", "")).resolve() != root:
                raise LiveDevError("native-source-mismatch")
        _build(_build_command(build), root)
    if not executable.is_file() or not os.access(executable, os.X_OK):
        raise LiveDevError("missing-executable")
    env = dict(os.environ)
    paths = str(root / "assets/lua/?.fnl") + ";" + str(root / "assets/lua/?/init.fnl")
    assets = [str(root / "assets")]
    assets.extend(str(Path(path).absolute()) for path in env.get("SPACE_ASSETS_PATH", "").split(os.pathsep) if path)
    env.update(SPACE_ASSETS_PATH=os.pathsep.join(dict.fromkeys(assets)), FENNEL_PATH=paths, FENNEL_MACRO_PATH=paths)
    return {"executable": str(executable), "argv": ["-m", "main", "--remote-control=auto"],
            "cwd": str(build), "environment": env}


def _launch(root, recipe):
    logs = _private_directory(_partition(root) / "logs")
    with _owned_file(logs / "app.log", os.O_CREAT | os.O_WRONLY | os.O_APPEND) as fd:
        try:
            return subprocess.Popen([recipe["executable"], *recipe["argv"]], cwd=recipe["cwd"],
                                    env=recipe["environment"], stdin=subprocess.DEVNULL, stdout=fd,
                                    stderr=fd, start_new_session=True)
        except (OSError, ValueError):
            raise LiveDevError("launch-failed") from None


def _wait_started(root, child, timeout, previous=None):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if child.poll() is not None:
            raise LiveDevError("startup-exited", exit=child.returncode)
        try:
            instances = discover(root, timeout=min(1, max(0.01, deadline - time.monotonic())))
        except LiveDevError as error:
            if error.code != "unavailable":
                raise
            # Publication can precede the first engine callback during startup.
            # Keep the launch lock and wait, never interpret this as absence.
            instances = []
        matches = [record for record in instances if record["pid"] == child.pid and record["ready"]
                   and record["instance-id"] != previous]
        if len(matches) == 1:
            return matches[0]
        time.sleep(0.05)
    raise LiveDevError("startup-timeout", pid=child.pid)


def _check_pending_launch(root, instances=None):
    """A missing app record never disowns a child launched by this checkout."""
    path = _partition(root) / "launch.json"
    try:
        intent = _read_json(path)
        if (not isinstance(intent, dict) or type(intent.get("schema-version")) not in (int, float)
                or intent["schema-version"] != 1
                or intent.get("checkout-root") != str(root)
                or intent.get("state") not in ("pending", "spawned")):
            raise LiveDevError("invalid-launch-record")
        if intent["state"] == "pending":
            # Interrupted capture: no inference from missing publication/PID.
            raise LiveDevError("startup-unverified")
        record = _validate_process_identity(intent["process"], root)
    except FileNotFoundError:
        return
    except (OSError, ValueError, KeyError, TypeError):
        raise LiveDevError("invalid-launch-record") from None
    try:
        _check_process(record)
    except LiveDevError as error:
        if error.code != "stale-instance":
            raise
        path.unlink()
        return
    if instances is None:
        instances = discover(root)
    for instance in instances:
        if instance.get("ready") is True and all(instance.get(key) == record[key] for key in PROCESS_IDENTITY if key != "instance-id"):
            path.unlink()
            return
    raise LiveDevError("startup-in-progress", pid=record["pid"])


def _launch_and_wait(root, recipe, timeout, previous=None):
    _check_pending_launch(root)
    path = _partition(root) / "launch.json"
    # Persist intent before Popen. Only public image/process identity is stored;
    # argv, environment, and all other recipe context remain in memory.
    executable = Path(recipe["executable"]).resolve(strict=True)
    image = _executable_identity(executable)
    intent = {"schema-version": 1, "checkout-root": str(root), "state": "pending"}
    _write_json(path, intent)
    try:
        child = _launch(root, recipe)
    except LiveDevError as error:
        if error.code == "launch-failed":  # Popen confirmed that no child exec'd.
            path.unlink()
        raise
    try:
        # This exact direct child has not been polled/reaped: PID reuse cannot
        # race capture. Verify the intended kernel image, not PID alone.
        proc = Path("/proc") / str(child.pid)
        record = {"instance-id": "launch-" + uuid.uuid4().hex, "checkout-root": str(root),
                  "pid": child.pid, "uid": proc.stat().st_uid,
                  "boot-id": Path("/proc/sys/kernel/random/boot_id").read_text().strip(),
                  "process-start": (proc / "stat").read_text().rsplit(")", 1)[1].split()[19],
                  "executable": str(executable), "executable-identity": image}
        _check_process(record)
        _write_json(path, dict(intent, state="spawned", process=record))
        result = _wait_started(root, child, timeout, previous)
        if any(result.get(key) != record[key] for key in PROCESS_IDENTITY if key != "instance-id"):
            raise LiveDevError("identity-mismatch")
        _check_process(record)
    except BaseException:
        # A timeout/error does not release ownership of a living child. The
        # next invocation can clear only proven exit or verified publication.
        if child.poll() is not None:
            path.unlink()
            raise LiveDevError("startup-exited", exit=child.returncode) from None
        raise
    path.unlink()
    return result


def _stale_preference(saved):
    try:
        _check_process(saved)
    except LiveDevError as error:
        if error.code == "stale-instance":
            return
        raise
    raise LiveDevError("unavailable", **{"instance-id": saved["instance-id"]})


def _choose_preferred(instances, saved):
    if saved is not None:
        try:
            return choose_instance(instances, saved)
        except LiveDevError as error:
            if error.code != "stale-selection":
                raise
            _stale_preference(saved)
    return choose_instance(instances, None)


def ensure_started(repo_root, timeout=30, selection=None, saved_selection=None):
    root = canonical_checkout(repo_root)
    with _checkout_lock(root, timeout):
        instances = discover(root)
        _check_pending_launch(root, instances)
        if selection is not None:
            return choose_instance(instances, selection)
        if instances:
            return _choose_preferred(instances, saved_selection)
        if saved_selection is not None:
            _stale_preference(saved_selection)
        return _launch_and_wait(root, _default_recipe(root), timeout)


def _recipe(instance, timeout):
    recipe = remote_request(instance, {"action": "launch-recipe"}, timeout)
    # Task 2 returns argv and the original environment; build metadata is public.
    if (not isinstance(recipe, dict) or recipe.get("executable") != instance["executable"]
            or not isinstance(recipe.get("argv"), list)
            or not all(isinstance(arg, str) for arg in recipe["argv"])
            or not isinstance(recipe.get("cwd"), str) or not Path(recipe["cwd"]).is_absolute()
            or not isinstance(recipe.get("environment"), dict)
            or not all(isinstance(key, str) and isinstance(value, str)
                       for key, value in recipe["environment"].items())):
        raise LiveDevError("invalid-launch-recipe")
    return recipe


def _validate_rebuild(root, instance):
    if Path(instance["native-source-root"]).resolve() != root:
        raise LiveDevError("native-source-mismatch")
    build = Path(instance["native-build-root"])
    cache = _cache(build)
    if (Path(cache.get("CMAKE_HOME_DIRECTORY:INTERNAL", "")).resolve() != root
            or cache.get("SPACE_BUILD_PROFILE:STRING") != instance["build-profile"]
            or cache.get("SPACE_ENABLE_CEF:BOOL", "").upper() not in
            (("ON", "TRUE", "1", "YES") if instance["cef-enabled"] else ("OFF", "FALSE", "0", "NO"))):
        raise LiveDevError("build-profile-mismatch")
    return build


def _rebuild(root, instance):
    build = _validate_rebuild(root, instance)
    _build(_build_command(build), root)


def _remaining(deadline):
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        raise LiveDevError("operation-timeout")
    return remaining


def _operation_identity(result, instance, request_id, action):
    if not isinstance(result, dict) or result.get("instance-id") != instance["instance-id"]:
        raise LiveDevError("operation-unverified", **{"request-id": request_id})
    if (type(result.get("request-id")) not in (int, float)
            or result["request-id"] != request_id or result.get("action") != action):
        raise LiveDevError("operation-conflict", **{"request-id": request_id})
    if result.get("status") not in ("pending", "running", "succeeded", "failed"):
        raise LiveDevError("operation-unverified", **{"request-id": request_id})


def _operate_locked(instance, action, deadline, wait=True):
    status = remote_request(instance, {"action": "status"}, min(_remaining(deadline), 2))
    request_id = status["next-request-id"]
    if (type(request_id) not in (int, float) or not 0 < request_id < 9007199254740991
            or int(request_id) != request_id):
        raise LiveDevError("operation-unverified")
    # Expiry after status must not authorize even a single mutation submission.
    submission_budget = min(_remaining(deadline), 2)
    try:
        result = remote_request(instance, {"action": action, "request-id": request_id}, submission_budget)
        _operation_identity(result, instance, request_id, action)
        _remaining(deadline)
        while wait and result["status"] in ("pending", "running"):
            time.sleep(min(0.05, _remaining(deadline)))
            result = remote_request(instance, {"action": "operation", "request-id": request_id}, _remaining(deadline))
            _operation_identity(result, instance, request_id, action)
            _remaining(deadline)
    except LiveDevError as error:
        error.details["mutation-submitted"] = True
        raise
    return result


def _operate(instance, action, timeout):
    deadline = time.monotonic() + timeout
    with _checkout_lock(Path(instance["checkout-root"]), timeout):
        return _operate_locked(instance, action, deadline)


@contextmanager
def _verified_pidfd(instance):
    instance = _validate_record(instance, Path(instance["checkout-root"]))
    fd = None
    try:
        if hasattr(os, "pidfd_open") and hasattr(signal, "pidfd_send_signal"):
            fd = os.pidfd_open(instance["pid"])
        _check_process(instance)
        yield fd
    except ProcessLookupError:
        raise LiveDevError("stale-instance") from None
    finally:
        if fd is not None:
            os.close(fd)


def _exited(instance, pidfd):
    if pidfd is not None:
        return bool(select.select([pidfd], [], [], 0)[0])
    try:
        _check_process(instance)
        return False
    except LiveDevError as error:
        if error.code != "stale-instance":
            raise
        return True


def _await_exit(instance, pidfd, timeout):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if _exited(instance, pidfd):
            return
        time.sleep(0.05)
    if pidfd is None:
        raise LiveDevError("unsafe-stop", reason="verified pidfd unavailable; refusing PID-only signaling")
    if _exited(instance, pidfd):
        return
    _check_process(instance)
    signal.pidfd_send_signal(pidfd, signal.SIGTERM)
    if not select.select([pidfd], [], [], min(timeout, 2))[0]:
        _check_process(instance)
        signal.pidfd_send_signal(pidfd, signal.SIGKILL)
        if not select.select([pidfd], [], [], min(timeout, 2))[0]:
            raise LiveDevError("stop-timeout")


def _stop_instance(instance, timeout):
    try:
        with _verified_pidfd(instance) as pidfd:
            try:
                _operate_locked(instance, "quit", time.monotonic() + timeout, wait=False)
            except LiveDevError as error:
                if error.code == "operation-conflict":
                    raise
                if pidfd is None:
                    raise LiveDevError("unsafe-stop") from None
                _check_process(instance)
            _await_exit(instance, pidfd, timeout)
    except LiveDevError as error:
        if error.code != "stale-instance":
            raise
        # Previously verified process exited; never signal a reused PID.


def _instance_set(instances, excluding=None):
    return {record["instance-id"]: {key: record[key] for key in IDENTITY}
            for record in instances if record["instance-id"] != excluding}


def _restart_peer_snapshot(root, instance, timeout):
    # Exact selected target may have lost RC after verified acceptance. Its
    # metadata and full kernel image still must match; peers require RPC too.
    try:
        _check_process(instance)
    except LiveDevError as error:
        if error.code != "stale-instance":
            raise
    peers = []
    target_registered = False
    for path, record in _registered_records(root):
        try:
            if record["instance-id"] == instance["instance-id"]:
                if any(record[key] != instance[key] for key in IDENTITY):
                    raise LiveDevError("replacement-conflict")
                _check_process(record)
                target_registered = True
            else:
                peers.append(verify_instance(record, root, min(timeout, 2)))
        except LiveDevError as error:
            if error.code != "stale-instance":
                raise
            _remove_stale(path, record)
    return peers, target_registered


def _restart_locked(root, instance, recipe, rebuild, timeout, authorized_peers):
    # Revalidate after ownership acquisition. Never promote a replacement or
    # newcomer seen while waiting into the previously authorized peer set.
    _check_pending_launch(root)
    peers, _target_registered = _restart_peer_snapshot(root, instance, timeout)
    if _instance_set(peers) != authorized_peers:
        raise LiveDevError("replacement-conflict", candidates=peers)
    if rebuild:
        _validate_rebuild(root, instance)
    _stop_instance(instance, timeout)
    if rebuild:
        _rebuild(root, instance)
    remaining = discover(root)
    if _instance_set(remaining) != authorized_peers:
        raise LiveDevError("replacement-conflict", candidates=remaining)
    replacement = _launch_and_wait(root, recipe, timeout, instance["instance-id"])
    if _instance_set(discover(root), replacement["instance-id"]) != authorized_peers:
        raise LiveDevError("replacement-conflict")
    _save_selection(root, replacement)
    return replacement


def _restart_authorization(root, instance, timeout):
    peers, target_registered = _restart_peer_snapshot(root, instance, timeout)
    if peers and not target_registered:
        raise LiveDevError("stale-restart-target")
    return _instance_set(peers)


def restart_instance(repo_root, instance, recipe, rebuild=False, timeout=30, *, _authorized_peers=None):
    root = canonical_checkout(repo_root)
    instance = _validate_record(instance, root)
    if _authorized_peers is None:
        _authorized_peers = _restart_authorization(root, instance, timeout)
    with _checkout_lock(root, timeout):
        return _restart_locked(root, instance, recipe, rebuild, timeout, _authorized_peers)


def _reload(root, instance, timeout):
    recipe = _recipe(instance, min(timeout, 2))
    authorized_peers = _restart_authorization(root, instance, timeout)
    try:
        result = _operate(instance, "reload", timeout)
    except LiveDevError as error:
        uncertain = error.details.get("mutation-submitted", False) and error.code != "operation-conflict"
        result = {"status": "unverified" if uncertain else "failed", "error": error.code, **error.details}
    if result["status"] == "succeeded":
        return result, 0
    output = {"status": "failed", "reload": result}
    if result["status"] == "unverified" or result.get("recovery-required"):
        try:
            replacement = restart_instance(root, instance, recipe, timeout=timeout, _authorized_peers=authorized_peers)
            output["recovery"] = {"status": "succeeded", "instance-id": replacement["instance-id"]}
        except LiveDevError as error:
            output["recovery"] = {"status": "failed", "error": error.code}
    return output, 1


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("discover", "start", "select", "status", "manual", "reload", "restart"))
    parser.add_argument("--repo-root", default=".")
    parser.add_argument("--instance")
    parser.add_argument("--request-id", type=int)
    parser.add_argument("--rebuild", action="store_true")
    parser.add_argument("--timeout", type=float, default=30)
    args = parser.parse_args(argv)
    try:
        if not math.isfinite(args.timeout) or args.timeout <= 0:
            raise LiveDevError("invalid-timeout")
        if (args.rebuild and args.command != "restart") or (args.request_id is not None and args.command != "status"):
            raise LiveDevError("invalid-options")
        root = canonical_checkout(args.repo_root)
        if args.command == "discover":
            output, exit_code = {"instances": discover(root, min(args.timeout, 2))}, 0
        else:
            saved = _load_selection(root) if args.instance is None else None
            if args.command == "start":
                instance = ensure_started(root, args.timeout, args.instance, saved_selection=saved)
            else:
                instances = discover(root, min(args.timeout, 2))
                instance = choose_instance(instances, args.instance) if args.instance is not None else _choose_preferred(instances, saved)
            if args.command in ("start", "select"):
                _save_selection(root, instance)
                output, exit_code = _public(instance), 0
            elif args.command == "reload":
                output, exit_code = _reload(root, instance, args.timeout)
            elif args.command == "restart":
                recipe = _recipe(instance, min(args.timeout, 2))
                # Validate before stopping: a fixture must not rebuild the user binary.
                if args.rebuild:
                    _validate_rebuild(root, instance)
                output = _public(restart_instance(root, instance, recipe, args.rebuild, args.timeout,
                                                  _authorized_peers=_instance_set(instances, instance["instance-id"])))
                exit_code = 0
            elif args.command == "manual":
                output = _operate(instance, "manual", args.timeout)
                exit_code = int(output["status"] != "succeeded")
            else:
                request = {"action": "operation", "request-id": args.request_id} if args.request_id is not None else {"action": "status"}
                output = remote_request(instance, request, min(args.timeout, 2))
                exit_code = int(output.get("status") == "failed" or output.get("faulted", False))
        print(json.dumps(output, ensure_ascii=False))
        return exit_code
    except LiveDevError as error:
        print(json.dumps({"status": "failed", "error": error.code, **error.details}))
        return 1
    except (OSError, ValueError, KeyError, TypeError):
        print(json.dumps({"status": "failed", "error": "lifecycle-unverified"}))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
