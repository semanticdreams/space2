cmake_minimum_required(VERSION 3.18)

add_library(date_date INTERFACE)
target_include_directories(date_date INTERFACE ${CMAKE_CURRENT_SOURCE_DIR}/include)
add_library(date::date ALIAS date_date)

find_package(Threads REQUIRED)

add_library(date_tz STATIC src/tz.cpp)
target_include_directories(date_tz PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/include)
target_compile_features(date_tz PUBLIC cxx_std_17)
if(WIN32)
    set(SPACE_WINDOWS_TZDATA_DIR "${CMAKE_CURRENT_SOURCE_DIR}/tzdata" CACHE PATH
        "Bundled IANA tzdb source directory used by date/tz on Windows")
    foreach(_space_tzdata_file IN ITEMS
        africa
        antarctica
        asia
        australasia
        backward
        etcetera
        europe
        northamerica
        southamerica
        leapseconds
        version
        windowsZones.xml
        LICENSE
        CLDR-LICENSE.txt
    )
        if(NOT EXISTS "${SPACE_WINDOWS_TZDATA_DIR}/${_space_tzdata_file}")
            message(FATAL_ERROR
                "Required Windows temporal tzdata file missing: ${SPACE_WINDOWS_TZDATA_DIR}/${_space_tzdata_file}")
        endif()
    endforeach()
    target_compile_definitions(date_tz PUBLIC
        USE_OS_TZDB=0
        HAS_REMOTE_API=0
        AUTO_DOWNLOAD=0
        INSTALL=.
    )
    target_link_libraries(date_tz PUBLIC advapi32)
else()
    target_compile_definitions(date_tz PUBLIC
        USE_OS_TZDB=1
        HAS_REMOTE_API=0
        AUTO_DOWNLOAD=0
    )
endif()
target_link_libraries(date_tz PUBLIC date_date Threads::Threads)
add_library(date::date-tz ALIAS date_tz)
