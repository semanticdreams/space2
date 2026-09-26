#include "lua_temporal_core.h"

#include "temporal.h"

#include <cstdint>
#include <stdexcept>
#include <string>

namespace
{
using space::temporal::CivilFields;
using space::temporal::Clock;
using space::temporal::Disambiguation;
using space::temporal::Duration;
using space::temporal::Instant;
using space::temporal::PlainDateTime;
using space::temporal::ZonedDateTime;

sol::table civil_fields_to_table(sol::this_state state, const CivilFields& fields)
{
    sol::state_view lua(state);
    sol::table table = lua.create_table();
    table["year"] = fields.year;
    table["month"] = fields.month;
    table["day"] = fields.day;
    table["hour"] = fields.hour;
    table["minute"] = fields.minute;
    table["second"] = fields.second;
    table["nanosecond"] = fields.nanosecond;
    return table;
}

template <typename T>
T require_present_field(const sol::table& table, const char* key)
{
    sol::object value = table.get<sol::object>(key);
    if (!value.valid() || value.is<sol::nil_t>())
    {
        throw std::invalid_argument(std::string("missing temporal field: ") + key);
    }

    if (!value.is<T>())
    {
        throw std::invalid_argument(std::string("invalid temporal field type: ") + key);
    }
    return value.as<T>();
}

template <typename T>
T optional_field(const sol::table& table, const char* key, T default_value)
{
    sol::object value = table.get<sol::object>(key);
    if (!value.valid() || value.is<sol::nil_t>())
    {
        return default_value;
    }

    if (!value.is<T>())
    {
        throw std::invalid_argument(std::string("invalid temporal field type: ") + key);
    }
    return value.as<T>();
}

template <typename T>
T optional_argument(sol::object value, const char* name, T default_value)
{
    if (!value.valid() || value.is<sol::nil_t>())
    {
        return default_value;
    }

    if (!value.is<T>())
    {
        throw std::invalid_argument(std::string("invalid temporal argument type: ") + name);
    }
    return value.as<T>();
}

Disambiguation optional_disambiguation(sol::object value)
{
    if (!value.valid() || value.is<sol::nil_t>())
    {
        return Disambiguation::Reject;
    }

    if (!value.is<std::string>())
    {
        throw std::invalid_argument("invalid temporal disambiguation type");
    }
    return space::temporal::parse_disambiguation(value.as<std::string>());
}

void register_temporal_types(sol::state& lua)
{
    lua.new_usertype<Duration>(
        "TemporalDuration",
        sol::no_constructor,
        "nanoseconds", &Duration::nanoseconds,
        "to-string", &Duration::to_string);

    lua.new_usertype<Instant>(
        "TemporalInstant",
        sol::no_constructor,
        "epoch-seconds", &Instant::epoch_seconds,
        "nanosecond", &Instant::nanosecond,
        "to-string", &Instant::to_string,
        "add", [](const Instant& self, const Duration& duration) {
            return self.add(duration);
        },
        "since", [](const Instant& self, const Instant& earlier) {
            return self.since(earlier);
        });

    lua.new_usertype<PlainDateTime>(
        "TemporalPlainDateTime",
        sol::no_constructor,
        "fields", [](const PlainDateTime& self, sol::this_state state) {
            return civil_fields_to_table(state, self.fields());
        },
        "to-string", &PlainDateTime::to_string,
        "add-days", [](const PlainDateTime& self, int days) {
            return self.add_days(days);
        },
        "iso-weekday", &PlainDateTime::iso_weekday);

    lua.new_usertype<ZonedDateTime>(
        "TemporalZonedDateTime",
        sol::no_constructor,
        "instant", &ZonedDateTime::instant,
        "zone-id", &ZonedDateTime::zone_id,
        "fields", [](const ZonedDateTime& self, sol::this_state state) {
            return civil_fields_to_table(state, self.fields());
        },
        "offset-string", &ZonedDateTime::offset_string,
        "to-string", &ZonedDateTime::to_string);

    lua.new_usertype<Clock>(
        "TemporalClock",
        sol::no_constructor,
        "now", &Clock::now);
}

sol::table create_temporal_core_table(sol::this_state state)
{
    sol::state_view lua(state);
    sol::table module = lua.create_table();

    sol::table duration = lua.create_table();
    duration.set_function("from-nanoseconds", [](std::int64_t nanoseconds) {
        return Duration::from_nanoseconds(nanoseconds);
    });
    duration.set_function("from-seconds", [](std::int64_t seconds) {
        return Duration::from_seconds(seconds);
    });
    duration.set_function("from-parts", [](sol::table parts) {
        return Duration::from_parts(optional_field<std::int64_t>(parts, "seconds", 0),
                                    optional_field<std::int64_t>(parts, "milliseconds", 0),
                                    optional_field<std::int64_t>(parts, "microseconds", 0),
                                    optional_field<std::int64_t>(parts, "nanoseconds", 0));
    });
    module["duration"] = duration;

    sol::table instant = lua.create_table();
    instant.set_function("parse", [](const std::string& text) {
        return Instant::parse(text);
    });
    instant.set_function("from-unix", [](std::int64_t epoch_seconds, sol::object nanosecond) {
        return Instant::from_unix(epoch_seconds,
                                  optional_argument<std::int32_t>(nanosecond, "nanosecond", 0));
    });
    module["instant"] = instant;

    sol::table plain_date_time = lua.create_table();
    plain_date_time.set_function("parse", [](const std::string& text) {
        return PlainDateTime::parse(text);
    });
    plain_date_time.set_function("from-fields", [](sol::table fields) {
        return PlainDateTime::from_fields(require_present_field<int>(fields, "year"),
                                          require_present_field<int>(fields, "month"),
                                          require_present_field<int>(fields, "day"),
                                          optional_field<int>(fields, "hour", 0),
                                          optional_field<int>(fields, "minute", 0),
                                          optional_field<int>(fields, "second", 0),
                                          optional_field<int>(fields, "nanosecond", 0));
    });
    module["plain-date-time"] = plain_date_time;

    sol::table zoned_date_time = lua.create_table();
    zoned_date_time.set_function("from-plain", [](const PlainDateTime& local,
                                                   const std::string& zone_id,
                                                   sol::object disambiguation) {
        return ZonedDateTime::from_plain(local, zone_id, optional_disambiguation(disambiguation));
    });
    zoned_date_time.set_function("from-instant", [](const Instant& value, const std::string& zone_id) {
        return ZonedDateTime::from_instant(value, zone_id);
    });
    module["zoned-date-time"] = zoned_date_time;

    sol::table clock = lua.create_table();
    clock.set_function("system", [] {
        return Clock::system();
    });
    clock.set_function("fixed", [](const Instant& value) {
        return Clock::fixed(value);
    });
    module["clock"] = clock;

    sol::table tzdb = lua.create_table();
    tzdb.set_function("version", [] {
        return space::temporal::tzdb_version();
    });
    module["tzdb"] = tzdb;

    return module;
}

} // namespace

void lua_bind_temporal_core(sol::state& lua)
{
    register_temporal_types(lua);

    sol::table package = lua["package"];
    sol::table preload = package["preload"];
    preload.set_function("temporal-core", [](sol::this_state state) {
        return create_temporal_core_table(state);
    });
}
