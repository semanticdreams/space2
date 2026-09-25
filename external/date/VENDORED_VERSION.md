# Howard Hinnant date/tz vendored snapshot

Source: https://github.com/HowardHinnant/date
Version: v3.0.1
Purpose: C++17 Gregorian calendar, RFC3339 parsing support, and IANA timezone handling for Space temporal core.
Local policy: Unix-like builds use the operating-system timezone database. Windows builds use the bundled IANA tzdata snapshot in `external/date/tzdata`, copied beside the packaged executables as `tzdata/`. Remote timezone database download/update paths are disabled.

## Bundled Windows tzdata

- IANA source: https://data.iana.org/time-zones/releases/tzdata2025b.tar.gz
- IANA version: 2025b
- CLDR `windowsZones.xml` source: https://raw.githubusercontent.com/unicode-org/cldr/release-46-1/common/supplemental/windowsZones.xml
- CLDR version: release-46-1
- Update policy: refresh this directory deliberately during dependency maintenance by replacing the IANA snapshot from an IANA release tarball and `windowsZones.xml` from a pinned CLDR release, updating this version note, and rerunning temporal native/Fennel validation. Runtime network download remains disabled (`HAS_REMOTE_API=0`, `AUTO_DOWNLOAD=0`).
