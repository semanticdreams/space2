#include <cstdlib>
#include <exception>
#include <iostream>

#include <sol/sol.hpp>

#include "lua_temporal_core.h"

int main()
{
    try
    {
        sol::state lua;
        lua.open_libraries(sol::lib::base,
                           sol::lib::package,
                           sol::lib::table,
                           sol::lib::string,
                           sol::lib::math);
        lua_bind_temporal_core(lua);

        lua.script(R"(
            local core = require("temporal-core")

            local one = core.duration["from-seconds"](1)
            local two = core.duration["from-seconds"](2)
            assert(one.compare(one, two) == -1)
            assert(two.compare(two, one) == 1)
            assert(one.compare(one, core.duration["from-seconds"](1)) == 0)

            local instant = core.instant.parse("2026-09-25T08:34:56-04:00")
            assert(instant["to-string"](instant) == "2026-09-25T12:34:56Z")

            local instant_a = core.instant.parse("2026-09-25T12:00:00Z")
            local instant_b = core.instant.parse("2026-09-25T12:00:01Z")
            assert(instant_a.compare(instant_a, instant_b) == -1)
            assert(instant_b.compare(instant_b, instant_a) == 1)

            local duration = core.duration["from-parts"]({
                seconds = 90,
                milliseconds = 500,
                microseconds = 0,
                nanoseconds = 0
            })
            local added = instant.add(instant, duration)
            assert(added["to-string"](added) == "2026-09-25T12:36:26.5Z")

            local plain = core["plain-date-time"].parse("2026-11-01T01:30:00")
            assert(plain.fields(plain).year == 2026)

            local plain_start = core["plain-date-time"].parse("2026-09-25T12:00:00")
            local shifted = plain_start.add(plain_start, core.duration["from-seconds"](90))
            assert(shifted["to-string"](shifted) == "2026-09-25T12:01:30")
            local elapsed = shifted.since(shifted, plain_start)
            assert(elapsed["to-string"](elapsed) == "PT1M30S")
            assert(plain_start.compare(plain_start, shifted) == -1)

            local leap_plain = core["plain-date-time"].parse("2028-02-28T10:11:12")
            local leap_next = leap_plain["add-days"](leap_plain, 1)
            assert(leap_next["to-string"](leap_next) == "2028-02-29T10:11:12")
            assert(leap_next["iso-weekday"](leap_next) == 2)

            local earliest = core["zoned-date-time"]["from-plain"](plain, "America/New_York", "earliest")
            local earliest_instant = earliest.instant(earliest)
            assert(earliest_instant["to-string"](earliest_instant) == "2026-11-01T05:30:00Z")

            local clock = core.clock.fixed(instant)
            local now = clock.now(clock)
            assert(now["to-string"](now) == "2026-09-25T12:34:56Z")

            assert(type(core.tzdb.version()) == "string")
            assert(core.tzdb.version() ~= "")

            local ok = pcall(function()
                core.instant.parse("2026-09-25T12:34:56")
            end)
            assert(ok == false)

            ok = pcall(function()
                core["zoned-date-time"]["from-plain"](plain, "Mars/Base", "reject")
            end)
            assert(ok == false)

            ok = pcall(function()
                core.duration["from-parts"]({ seconds = {} })
            end)
            assert(ok == false)

            ok = pcall(function()
                core.instant["from-unix"](0, {})
            end)
            assert(ok == false)

            ok = pcall(function()
                core["plain-date-time"]["from-fields"]({
                    year = 2026,
                    month = 9,
                    day = 25,
                    hour = {}
                })
            end)
            assert(ok == false)

            local unambiguous_plain = core["plain-date-time"].parse("2026-09-25T12:00:00")
            local default_reject = core["zoned-date-time"]["from-plain"](unambiguous_plain, "America/New_York")
            assert(default_reject.instant(default_reject)["to-string"](default_reject.instant(default_reject)) == "2026-09-25T16:00:00Z")

            ok = pcall(function()
                core["zoned-date-time"]["from-plain"](unambiguous_plain, "America/New_York", {})
            end)
            assert(ok == false)

            ok = pcall(function()
                core["zoned-date-time"]["from-plain"](unambiguous_plain, "America/New_York", "middle")
            end)
            assert(ok == false)
        )");
    }
    catch (const std::exception& ex)
    {
        std::cerr << "test_lua_temporal_core_binding failure: " << ex.what() << '\n';
        return EXIT_FAILURE;
    }

    return EXIT_SUCCESS;
}
