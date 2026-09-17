from pathlib import Path
import re


REPO_ROOT = Path(__file__).resolve().parents[2]


def read_repo_text(relative_path: str) -> str:
    return (REPO_ROOT / relative_path).read_text(encoding="utf-8")


def test_mingw_epoxy_imported_target_filters_host_include_directories() -> None:
    cmake = read_repo_text("CMakeLists.txt")
    epoxy_pkg_check = "pkg_check_modules(EPOXY REQUIRED IMPORTED_TARGET epoxy)"

    assert epoxy_pkg_check in cmake

    _, epoxy_following_cmake = cmake.split(epoxy_pkg_check, 1)
    mingw_filter = re.search(
        r"if\s*\([^)]*MINGW[^)]*\)(?P<body>.*?)endif\s*\(",
        epoxy_following_cmake,
        re.DOTALL,
    )

    assert mingw_filter is not None

    body = mingw_filter.group("body")
    assert "PkgConfig::EPOXY" in body
    assert "INTERFACE_INCLUDE_DIRECTORIES" in body
    assert "get_target_property" in body
    assert "set_target_properties" in body
    assert re.search(r"list\s*\(REMOVE_ITEM\b[^)]*/usr/include", body, re.DOTALL)
    assert re.search(r"list\s*\(REMOVE_ITEM\b[^)]*/usr/local/include", body, re.DOTALL)


def test_windows_smoke_rg_dependency_is_installed_and_guarded() -> None:
    setup_script = read_repo_text("scripts/setup-windows-build-host.sh")
    workflows = [
        ".github/workflows/test.yml",
        ".github/workflows/build.yml",
    ]

    for workflow_path in workflows:
        workflow = read_repo_text(workflow_path)
        assert "scripts/setup-windows-build-host.sh" in workflow
        assert "| rg " in workflow

    assert "ripgrep" in setup_script
    assert "command -v rg" in setup_script
    assert "Missing ripgrep after setup." in setup_script


def test_windows_build_host_installs_masm_compatible_llvm_ml() -> None:
    setup_script = read_repo_text("scripts/setup-windows-build-host.sh")

    assert "llvm-14" in setup_script


def test_windows_build_host_installs_and_verifies_zip() -> None:
    setup_script = read_repo_text("scripts/setup-windows-build-host.sh")

    assert "    zip" in setup_script
    assert "command -v zip" in setup_script
    assert "Missing zip after setup." in setup_script


def test_windows_build_host_installs_and_verifies_powershell_core() -> None:
    setup_script = read_repo_text("scripts/setup-windows-build-host.sh")

    assert "install_powershell_core" in setup_script
    assert "packages-microsoft-prod.deb" in setup_script
    assert "sudo apt-get install -y powershell" in setup_script
    assert "command -v pwsh" in setup_script
    assert "PowerShell Core (pwsh) is required by vcpkg." in setup_script


def test_windows_build_host_installs_and_verifies_autotools_for_vcpkg_ports() -> None:
    setup_script = read_repo_text("scripts/setup-windows-build-host.sh")

    assert "    autoconf" in setup_script
    assert "    automake" in setup_script
    assert "    libtool" in setup_script
    assert "command -v autoconf" in setup_script
    assert "Missing autoconf after setup." in setup_script


def test_windows_build_from_linux_defaults_requires_and_exports_masm_settings() -> None:
    build_script = read_repo_text("scripts/build-windows-from-linux.sh")

    assert 'CMAKE_ASM_MASM_COMPILER="${CMAKE_ASM_MASM_COMPILER:-llvm-ml-14}"' in build_script
    assert 'require_cmd "${CMAKE_ASM_MASM_COMPILER}" "Run scripts/setup-windows-build-host.sh"' in build_script
    assert 'export CMAKE_ASM_MASM_COMPILER' in build_script
    assert 'export CMAKE_ASM_MASM_FLAGS="${CMAKE_ASM_MASM_FLAGS:--m64}"' in build_script


def test_windows_build_from_linux_preflights_vcpkg_host_tools() -> None:
    build_script = read_repo_text("scripts/build-windows-from-linux.sh")

    assert 'require_cmd zip "Run scripts/setup-windows-build-host.sh"' in build_script
    assert 'require_cmd pwsh "Run scripts/setup-windows-build-host.sh"' in build_script
    assert 'require_cmd autoconf "Run scripts/setup-windows-build-host.sh"' in build_script


def test_windows_under_wine_resolves_wine_command_with_fallbacks() -> None:
    wine_script = read_repo_text("scripts/test-windows-under-wine.sh")

    assert "resolve_wine_cmd()" in wine_script
    assert "${WINE_CMD:-}" in wine_script
    assert "command -v wine64" in wine_script
    assert "command -v wine" in wine_script
    assert "Missing required command: wine64 or wine" in wine_script
    assert 'WINE_CMD="$(resolve_wine_cmd)"' in wine_script
    assert '"${WINE_CMD}" "${CLI_EXE}" -m "${TEST_MODULE}"' in wine_script
    assert "wine64 \"${CLI_EXE}\"" not in wine_script


def test_workflow_windows_smoke_uses_wine_fallback() -> None:
    workflow_paths = [
        ".github/workflows/test.yml",
        ".github/workflows/build.yml",
    ]

    for workflow_path in workflow_paths:
        workflow = read_repo_text(workflow_path)
        assert "WINE_CMD=wine64" in workflow
        assert "WINE_CMD=wine" in workflow
        assert "Missing required command: wine64 or wine" in workflow
        assert 'timeout 60s "${WINE_CMD}" build/windows/space-cli.exe --help >/dev/null' in workflow
        assert "timeout 60s wine64 build/windows/space-cli.exe --help >/dev/null" not in workflow


def test_gitignore_ignores_default_vcpkg_checkout() -> None:
    gitignore = read_repo_text(".gitignore")

    assert "/vcpkg/" in gitignore


def test_build_windows_passes_masm_settings_to_cmake_when_env_is_set() -> None:
    build_script = read_repo_text("scripts/build-windows.sh")

    assert 'if [ -n "${CMAKE_ASM_MASM_COMPILER:-}" ]; then' in build_script
    assert 'cmake_args+=(-DCMAKE_ASM_MASM_COMPILER="${CMAKE_ASM_MASM_COMPILER}")' in build_script
    assert 'if [ -n "${CMAKE_ASM_MASM_FLAGS:-}" ]; then' in build_script
    assert 'cmake_args+=(-DCMAKE_ASM_MASM_FLAGS="${CMAKE_ASM_MASM_FLAGS}")' in build_script
