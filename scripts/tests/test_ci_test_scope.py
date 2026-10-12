from scripts.ci_test_scope import classify


def test_pull_request_docs_only_skips_native_validation():
    decision = classify(
        "pull_request",
        ["docs/dev/notes/opencode-mcp-bridges.md", "README.md"],
    )
    assert decision.mode == "docs-only"
    assert decision.run_native is False
    assert decision.use_prebuilt_runtime is False
    assert decision.run_runtime_tests is False


def test_pull_request_assets_use_prebuilt_runtime_validation():
    decision = classify(
        "pull_request",
        ["assets/lua/tree-view.fnl", "assets/lua/tests/test-tree-view.fnl"],
    )
    assert decision.mode == "prebuilt-runtime"
    assert decision.run_native is False
    assert decision.use_prebuilt_runtime is True
    assert decision.run_runtime_tests is True


def test_pull_request_mixed_assets_and_docs_use_prebuilt_runtime_validation():
    decision = classify(
        "pull_request",
        ["assets/lua/tree-view.fnl", "docs/dev/features/tree-view-widget.md"],
    )
    assert decision.mode == "prebuilt-runtime"
    assert decision.use_prebuilt_runtime is True


def test_pull_request_native_path_requires_full_validation():
    decision = classify("pull_request", ["src/lua_engine.cpp"])
    assert decision.mode == "full-native"
    assert decision.run_native is True
    assert decision.use_prebuilt_runtime is False
    assert decision.run_runtime_tests is True
    assert "src/lua_engine.cpp" in decision.reason


def test_pull_request_workflow_path_requires_full_validation():
    decision = classify("pull_request", [".github/workflows/test.yml"])
    assert decision.mode == "full-native"
    assert decision.run_native is True
    assert decision.use_prebuilt_runtime is False


def test_push_to_main_never_uses_prebuilt_runtime_even_for_assets():
    decision = classify("push", ["assets/lua/tree-view.fnl"])
    assert decision.mode == "full-native"
    assert decision.run_native is True
    assert decision.use_prebuilt_runtime is False


def test_merge_group_never_uses_prebuilt_runtime_even_for_assets():
    decision = classify("merge_group", ["assets/lua/tree-view.fnl"])
    assert decision.mode == "full-native"
    assert decision.run_native is True
    assert decision.use_prebuilt_runtime is False


def test_empty_change_list_runs_full_validation():
    decision = classify("pull_request", [])
    assert decision.mode == "full-native"
    assert decision.run_native is True
    assert decision.use_prebuilt_runtime is False
