set(SPACE_TEMPORAL_DEPENDENCY_MANIFESTS
    "${CMAKE_CURRENT_SOURCE_DIR}/external/temporal/icu/DEPENDENCY_MANIFEST.json"
    "${CMAKE_CURRENT_SOURCE_DIR}/external/temporal/libical/DEPENDENCY_MANIFEST.json"
    "${CMAKE_CURRENT_SOURCE_DIR}/external/temporal/holidays/DEPENDENCY_MANIFEST.json"
)

set(SPACE_TEMPORAL_RUNTIME_MANIFEST
    "${CMAKE_CURRENT_SOURCE_DIR}/assets/temporal/manifest.json")

foreach(SPACE_TEMPORAL_MANIFEST IN LISTS SPACE_TEMPORAL_DEPENDENCY_MANIFESTS)
    if(NOT EXISTS "${SPACE_TEMPORAL_MANIFEST}")
        message(FATAL_ERROR "Missing temporal dependency manifest: ${SPACE_TEMPORAL_MANIFEST}")
    endif()
endforeach()

if(NOT EXISTS "${SPACE_TEMPORAL_RUNTIME_MANIFEST}")
    message(FATAL_ERROR "Missing temporal runtime manifest: ${SPACE_TEMPORAL_RUNTIME_MANIFEST}")
endif()

option(SPACE_TEMPORAL_ENABLE_ICU_ADAPTER "Enable future ICU temporal adapter" OFF)
option(SPACE_TEMPORAL_ENABLE_ICAL_ADAPTER "Enable future iCalendar temporal adapter" OFF)

if(SPACE_TEMPORAL_ENABLE_ICU_ADAPTER)
    message(FATAL_ERROR "SPACE_TEMPORAL_ENABLE_ICU_ADAPTER is reserved for a later temporal localization adapter track; this foundation only validates manifests.")
endif()

if(SPACE_TEMPORAL_ENABLE_ICAL_ADAPTER)
    message(FATAL_ERROR "SPACE_TEMPORAL_ENABLE_ICAL_ADAPTER is reserved for a later temporal iCalendar adapter track; this foundation only validates manifests.")
endif()
