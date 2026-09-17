from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
PORTFILE = REPO_ROOT / "scripts/vcpkg-ports/xapian/portfile.cmake"
CONFIGURE_DIFF = REPO_ROOT / "scripts/vcpkg-ports/xapian/configure.diff"


def read_portfile() -> str:
    return PORTFILE.read_text(encoding="utf-8")


def read_configure_diff() -> str:
    return CONFIGURE_DIFF.read_text(encoding="utf-8")


def mingw_block(portfile: str) -> str:
    start = portfile.index("if(VCPKG_TARGET_IS_MINGW)")
    configure = portfile.index("vcpkg_configure_make(")
    end = portfile.index("endif()", start)
    assert end < configure
    return portfile[start:end]


def test_xapian_mingw_port_keeps_only_fortify_override() -> None:
    portfile = read_portfile()
    block = mingw_block(portfile)

    assert "CPPFLAGS=-D_FORTIFY_SOURCE=0" in block
    assert "VCPKG_CXX_FLAGS" not in block
    assert "VCPKG_C_FLAGS" not in block
    assert "CXXFLAGS=-std=gnu++14" not in portfile


def test_xapian_configure_patch_forces_cxx14_for_mingw_and_preserves_zlib_flags() -> None:
    diff = read_configure_diff()

    assert "*-mingw*)" in diff
    assert "std::byte" in diff
    assert "MinGW" in diff
    assert "byte" in diff
    assert 'CXXFLAGS="$CXXFLAGS -std=gnu++14"' in diff
    assert 'CPPFLAGS="$CPPFLAGS $ZLIB_CFLAGS"' in diff
    assert 'LIBS="$ZLIB_LIBS $LIBS"' in diff
    assert 'CFLAGS="$LIBS $ZLIB_CFLAGS"' not in diff
