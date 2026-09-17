from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]


def read_repo_text(relative_path: str) -> str:
    return (REPO_ROOT / relative_path).read_text(encoding="utf-8")


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


def test_gitignore_ignores_default_vcpkg_checkout() -> None:
    gitignore = read_repo_text(".gitignore")

    assert "/vcpkg/" in gitignore


def test_build_windows_passes_masm_settings_to_cmake_when_env_is_set() -> None:
    build_script = read_repo_text("scripts/build-windows.sh")

    assert 'if [ -n "${CMAKE_ASM_MASM_COMPILER:-}" ]; then' in build_script
    assert 'cmake_args+=(-DCMAKE_ASM_MASM_COMPILER="${CMAKE_ASM_MASM_COMPILER}")' in build_script
    assert 'if [ -n "${CMAKE_ASM_MASM_FLAGS:-}" ]; then' in build_script
    assert 'cmake_args+=(-DCMAKE_ASM_MASM_FLAGS="${CMAKE_ASM_MASM_FLAGS}")' in build_script
