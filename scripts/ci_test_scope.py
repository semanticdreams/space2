#!/usr/bin/env python3
from __future__ import annotations

import argparse
from dataclasses import dataclass
from typing import Iterable


@dataclass(frozen=True)
class ScopeDecision:
    mode: str
    run_native: bool
    use_prebuilt_runtime: bool
    run_runtime_tests: bool
    reason: str


def _is_docs_only_path(path: str) -> bool:
    return path.startswith("docs/") or ("/" not in path and path.endswith(".md"))


def _is_asset_runtime_path(path: str) -> bool:
    return path.startswith("assets/") or _is_docs_only_path(path)


def classify(event_name: str, changed_paths: Iterable[str]) -> ScopeDecision:
    paths = [path for path in changed_paths if path]
    if not paths:
        return ScopeDecision(
            mode="full-native",
            run_native=True,
            use_prebuilt_runtime=False,
            run_runtime_tests=True,
            reason="no changed files detected; running full suite",
        )

    if event_name != "pull_request":
        return ScopeDecision(
            mode="full-native",
            run_native=True,
            use_prebuilt_runtime=False,
            run_runtime_tests=True,
            reason=f"full suite required for {event_name}",
        )

    if all(_is_docs_only_path(path) for path in paths):
        return ScopeDecision(
            mode="docs-only",
            run_native=False,
            use_prebuilt_runtime=False,
            run_runtime_tests=False,
            reason="docs-only change",
        )

    for path in paths:
        if not _is_asset_runtime_path(path):
            return ScopeDecision(
                mode="full-native",
                run_native=True,
                use_prebuilt_runtime=False,
                run_runtime_tests=True,
                reason=f"native-impacting change: {path}",
            )

    return ScopeDecision(
        mode="prebuilt-runtime",
        run_native=False,
        use_prebuilt_runtime=True,
        run_runtime_tests=True,
        reason="assets-only change; validating with trusted main runtime",
    )


def _bool(value: bool) -> str:
    return "true" if value else "false"


def main() -> int:
    parser = argparse.ArgumentParser(description="Classify CI validation scope from changed paths.")
    parser.add_argument("--event", required=True)
    parser.add_argument("--changed-file", action="append", default=[])
    args = parser.parse_args()
    decision = classify(args.event, args.changed_file)
    print(f"mode={decision.mode}")
    print(f"run-native={_bool(decision.run_native)}")
    print(f"use-prebuilt-runtime={_bool(decision.use_prebuilt_runtime)}")
    print(f"run-runtime-tests={_bool(decision.run_runtime_tests)}")
    print(f"reason={decision.reason}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
