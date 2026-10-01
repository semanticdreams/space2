# ICU/CLDR Runtime Data

This directory contains the deterministic `cldr-seed` corpus used by the first
`Temporal.localization` and `Temporal.calendar` Fennel facades.

The seed corpus is a hand-curated selected subset derived from CLDR 46 date
patterns, month names, and era identifiers. Runtime network fetches are not
allowed. Full ICU4C source, generated CLDR data, and the native
`temporal_localization` adapter remain future work.
