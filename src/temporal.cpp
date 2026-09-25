#include "temporal.h"

#include <date/tz.h>

#include <iomanip>
#include <limits>
#include <regex>
#include <sstream>
#include <stdexcept>
#include <utility>

namespace space::temporal
{
namespace
{
using Nanoseconds = std::chrono::nanoseconds;
using SysTime = date::sys_time<Nanoseconds>;
using LocalTime = date::local_time<Nanoseconds>;

constexpr std::int64_t nanos_per_second = 1000000000LL;
constexpr std::int64_t nanos_per_millisecond = 1000000LL;
constexpr std::int64_t nanos_per_microsecond = 1000LL;
constexpr std::int64_t seconds_per_day = 86400LL;
constexpr std::int64_t nanos_per_day = seconds_per_day * nanos_per_second;

std::int64_t checked_add(std::int64_t left, std::int64_t right)
{
    if ((right > 0 && left > std::numeric_limits<std::int64_t>::max() - right) ||
        (right < 0 && left < std::numeric_limits<std::int64_t>::min() - right))
    {
        throw std::overflow_error("temporal duration arithmetic overflow");
    }

    return left + right;
}

std::int64_t checked_subtract(std::int64_t left, std::int64_t right)
{
    if ((right < 0 && left > std::numeric_limits<std::int64_t>::max() + right) ||
        (right > 0 && left < std::numeric_limits<std::int64_t>::min() + right))
    {
        throw std::overflow_error("temporal duration arithmetic overflow");
    }

    return left - right;
}

std::int64_t checked_multiply(std::int64_t value, std::int64_t factor)
{
    if (value > 0)
    {
        if (factor > 0 && value > std::numeric_limits<std::int64_t>::max() / factor)
        {
            throw std::overflow_error("temporal duration arithmetic overflow");
        }
        if (factor < 0 && factor < std::numeric_limits<std::int64_t>::min() / value)
        {
            throw std::overflow_error("temporal duration arithmetic overflow");
        }
    }
    else if (value < 0)
    {
        if (factor > 0 && value < std::numeric_limits<std::int64_t>::min() / factor)
        {
            throw std::overflow_error("temporal duration arithmetic overflow");
        }
        if (factor < 0 && value != 0 && factor < std::numeric_limits<std::int64_t>::max() / value)
        {
            throw std::overflow_error("temporal duration arithmetic overflow");
        }
    }

    return value * factor;
}

void validate_time_fields(int hour, int minute, int second, int nanosecond)
{
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59 ||
        second < 0 || second > 59 || nanosecond < 0 || nanosecond >= nanos_per_second)
    {
        throw std::invalid_argument("invalid temporal time fields");
    }
}

date::year_month_day validate_date_fields(int year, int month, int day)
{
    if (year < static_cast<int>(date::year::min()) ||
        year > static_cast<int>(date::year::max()))
    {
        throw std::invalid_argument("invalid temporal date fields");
    }

    date::year_month_day ymd{date::year{year}, date::month{static_cast<unsigned>(month)},
                             date::day{static_cast<unsigned>(day)}};
    if (!ymd.ok())
    {
        throw std::invalid_argument("invalid temporal date fields");
    }
    return ymd;
}

std::int64_t checked_i128_to_i64(__int128 value, const char* message)
{
    if (value > static_cast<__int128>(std::numeric_limits<std::int64_t>::max()) ||
        value < static_cast<__int128>(std::numeric_limits<std::int64_t>::min()))
    {
        throw std::invalid_argument(message);
    }

    return static_cast<std::int64_t>(value);
}

int parse_int(const std::string& text)
{
    return std::stoi(text);
}

int parse_fraction(const std::string& fraction)
{
    if (fraction.empty())
    {
        return 0;
    }
    if (fraction.size() > 9)
    {
        throw std::invalid_argument("invalid temporal fractional second");
    }

    std::string padded = fraction;
    padded.append(9 - padded.size(), '0');
    return parse_int(padded);
}

__int128 nanos_from_fields(int year,
                           int month,
                           int day,
                           int hour,
                           int minute,
                           int second,
                           int nanosecond)
{
    const auto ymd = validate_date_fields(year, month, day);
    validate_time_fields(hour, minute, second, nanosecond);
    const auto days_since_epoch = date::local_days{ymd}.time_since_epoch().count();
    const __int128 day_nanos = static_cast<__int128>(days_since_epoch) * nanos_per_day;
    const __int128 time_nanos = static_cast<__int128>(hour) * 3600 * nanos_per_second +
                                static_cast<__int128>(minute) * 60 * nanos_per_second +
                                static_cast<__int128>(second) * nanos_per_second +
                                nanosecond;
    return day_nanos + time_nanos;
}

LocalTime checked_local_from_nanos(__int128 nanoseconds)
{
    return LocalTime{Nanoseconds{checked_i128_to_i64(
        nanoseconds, "temporal local date-time outside nanosecond range")}};
}

LocalTime local_from_fields(int year,
                            int month,
                            int day,
                            int hour,
                            int minute,
                            int second,
                            int nanosecond)
{
    return checked_local_from_nanos(
        nanos_from_fields(year, month, day, hour, minute, second, nanosecond));
}

CivilFields fields_from_local(LocalTime value)
{
    const auto day = date::floor<date::days>(value);
    const date::year_month_day ymd{day};
    const date::hh_mm_ss<Nanoseconds> time{value - day};
    return CivilFields{static_cast<int>(ymd.year()),
                       static_cast<int>(static_cast<unsigned>(ymd.month())),
                       static_cast<int>(static_cast<unsigned>(ymd.day())),
                       static_cast<int>(time.hours().count()),
                       static_cast<int>(time.minutes().count()),
                       static_cast<int>(time.seconds().count()),
                       static_cast<int>(time.subseconds().count())};
}

std::string format_fraction(int nanosecond)
{
    if (nanosecond == 0)
    {
        return "";
    }

    std::ostringstream out;
    out << '.' << std::setw(9) << std::setfill('0') << nanosecond;
    std::string value = out.str();
    while (value.back() == '0')
    {
        value.pop_back();
    }
    return value;
}

std::string format_civil(const CivilFields& fields)
{
    std::ostringstream out;
    out << std::setw(4) << std::setfill('0') << fields.year << '-'
        << std::setw(2) << fields.month << '-'
        << std::setw(2) << fields.day << 'T'
        << std::setw(2) << fields.hour << ':'
        << std::setw(2) << fields.minute << ':'
        << std::setw(2) << fields.second
        << format_fraction(fields.nanosecond);
    return out.str();
}

SysTime checked_sys_from_nanos(std::int64_t nanos)
{
    return SysTime{Nanoseconds{nanos}};
}

SysTime checked_sys_from_nanos(__int128 nanos)
{
    return SysTime{Nanoseconds{checked_i128_to_i64(
        nanos, "temporal instant outside nanosecond range")}};
}

SysTime checked_sys_from_seconds(std::int64_t seconds)
{
    return checked_sys_from_nanos(checked_multiply(seconds, nanos_per_second));
}

const date::time_zone* locate_zone_or_throw(const std::string& zone_id)
{
    const date::tzdb* database = nullptr;
    try
    {
        database = &date::get_tzdb();
    }
    catch (const std::runtime_error& ex)
    {
        throw std::runtime_error(std::string("temporal timezone database unavailable: ") + ex.what());
    }

    try
    {
        return database->locate_zone(zone_id);
    }
    catch (const std::runtime_error& ex)
    {
        throw std::invalid_argument(std::string("invalid temporal timezone: ") + ex.what());
    }
}

date::sys_info zone_info_for_instant(const std::string& zone_id, SysTime instant)
{
    const auto* zone = locate_zone_or_throw(zone_id);
    return zone->get_info(instant);
}

SysTime checked_sys_from_local_with_offset(LocalTime local, std::chrono::seconds offset)
{
    return checked_sys_from_nanos(checked_subtract(
        local.time_since_epoch().count(), checked_multiply(offset.count(), nanos_per_second)));
}

SysTime resolve_local(const date::time_zone& zone,
                      LocalTime local,
                      Disambiguation disambiguation)
{
    const auto info = zone.get_info(local);
    if (info.result == date::local_info::unique)
    {
        return checked_sys_from_local_with_offset(local, info.first.offset);
    }

    if (disambiguation == Disambiguation::Reject)
    {
        throw std::invalid_argument("rejected ambiguous or nonexistent temporal local time");
    }

    if (info.result == date::local_info::ambiguous)
    {
        return disambiguation == Disambiguation::Earliest
                   ? checked_sys_from_local_with_offset(local, info.first.offset)
                   : checked_sys_from_local_with_offset(local, info.second.offset);
    }

    return disambiguation == Disambiguation::Earliest
               ? checked_sys_from_seconds(info.second.begin.time_since_epoch().count())
               : checked_sys_from_nanos(checked_subtract(
                     checked_multiply(info.first.end.time_since_epoch().count(), nanos_per_second), 1));
}

} // namespace

Duration::Duration(Nanoseconds value)
    : value_(value)
{
}

Duration Duration::from_nanoseconds(std::int64_t nanoseconds)
{
    return Duration{Nanoseconds{nanoseconds}};
}

Duration Duration::from_seconds(std::int64_t seconds)
{
    return Duration{Nanoseconds{checked_multiply(seconds, nanos_per_second)}};
}

Duration Duration::from_parts(std::int64_t seconds,
                              std::int64_t milliseconds,
                              std::int64_t microseconds,
                              std::int64_t nanoseconds)
{
    std::int64_t total = checked_multiply(seconds, nanos_per_second);
    total = checked_add(total, checked_multiply(milliseconds, nanos_per_millisecond));
    total = checked_add(total, checked_multiply(microseconds, nanos_per_microsecond));
    total = checked_add(total, nanoseconds);
    return Duration{Nanoseconds{total}};
}

std::int64_t Duration::nanoseconds() const
{
    return value_.count();
}

std::string Duration::to_string() const
{
    return std::to_string(value_.count()) + "ns";
}

Instant::Instant(SysTime value)
    : value_(value)
{
}

Instant Instant::parse(const std::string& text)
{
    static const std::regex pattern{
        R"(^([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})(?:\.([0-9]{1,9}))?(Z|[+-][0-9]{2}:[0-9]{2})$)"};
    std::smatch match;
    if (!std::regex_match(text, match, pattern))
    {
        throw std::invalid_argument("invalid temporal instant");
    }

    const int second = parse_int(match[6]);
    if (second == 60)
    {
        throw std::invalid_argument("leap seconds are not supported");
    }

    const auto local_nanos = nanos_from_fields(parse_int(match[1]),
                                               parse_int(match[2]),
                                               parse_int(match[3]),
                                               parse_int(match[4]),
                                               parse_int(match[5]),
                                               second,
                                               parse_fraction(match[7]));
    const std::string offset = match[8];
    std::int64_t offset_seconds = 0;
    if (offset != "Z")
    {
        const int sign = offset[0] == '-' ? -1 : 1;
        const int hours = parse_int(offset.substr(1, 2));
        const int minutes = parse_int(offset.substr(4, 2));
        if (hours > 23 || minutes > 59)
        {
            throw std::invalid_argument("invalid temporal instant offset");
        }
        offset_seconds = sign * ((hours * 60 + minutes) * 60);
    }

    return Instant{checked_sys_from_nanos(
        local_nanos - static_cast<__int128>(offset_seconds) * nanos_per_second)};
}

Instant Instant::from_unix(std::int64_t epoch_seconds, std::int32_t nanosecond)
{
    if (nanosecond < 0 || nanosecond >= nanos_per_second)
    {
        throw std::invalid_argument("invalid instant nanosecond");
    }
    return Instant{checked_sys_from_nanos(
        checked_add(checked_multiply(epoch_seconds, nanos_per_second), nanosecond))};
}

std::int64_t Instant::epoch_seconds() const
{
    return date::floor<std::chrono::seconds>(value_).time_since_epoch().count();
}

std::int32_t Instant::nanosecond() const
{
    const auto seconds = date::floor<std::chrono::seconds>(value_);
    return static_cast<std::int32_t>((value_ - seconds).count());
}

std::string Instant::to_string() const
{
    return format_civil(fields_from_local(LocalTime{value_.time_since_epoch()})) + "Z";
}

Instant Instant::add(const Duration& duration) const
{
    const auto total = checked_add(value_.time_since_epoch().count(), duration.value_.count());
    return Instant{checked_sys_from_nanos(total)};
}

Duration Instant::since(const Instant& earlier) const
{
    return Duration{Nanoseconds{checked_subtract(value_.time_since_epoch().count(),
                                                earlier.value_.time_since_epoch().count())}};
}

bool Instant::operator==(const Instant& other) const
{
    return value_ == other.value_;
}

bool Instant::operator<(const Instant& other) const
{
    return value_ < other.value_;
}

PlainDateTime::PlainDateTime(LocalTime value)
    : value_(value)
{
}

PlainDateTime PlainDateTime::parse(const std::string& text)
{
    static const std::regex pattern{
        R"(^([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})(?:\.([0-9]{1,9}))?$)"};
    std::smatch match;
    if (!std::regex_match(text, match, pattern))
    {
        throw std::invalid_argument("invalid temporal plain date-time");
    }

    const int second = parse_int(match[6]);
    if (second == 60)
    {
        throw std::invalid_argument("leap seconds are not supported");
    }

    return PlainDateTime{local_from_fields(parse_int(match[1]),
                                           parse_int(match[2]),
                                           parse_int(match[3]),
                                           parse_int(match[4]),
                                           parse_int(match[5]),
                                           second,
                                           parse_fraction(match[7]))};
}

PlainDateTime PlainDateTime::from_fields(int year,
                                         int month,
                                         int day,
                                         int hour,
                                         int minute,
                                         int second,
                                         int nanosecond)
{
    return PlainDateTime{local_from_fields(year, month, day, hour, minute, second, nanosecond)};
}

CivilFields PlainDateTime::fields() const
{
    return fields_from_local(value_);
}

std::string PlainDateTime::to_string() const
{
    return format_civil(fields());
}

ZonedDateTime::ZonedDateTime(const Instant& instant, std::string zone_id)
    : instant_(instant)
    , zone_id_(std::move(zone_id))
{
}

ZonedDateTime ZonedDateTime::from_plain(const PlainDateTime& local,
                                        const std::string& zone_id,
                                        Disambiguation disambiguation)
{
    const auto* zone = locate_zone_or_throw(zone_id);
    return ZonedDateTime{Instant{resolve_local(*zone, local.value_, disambiguation)}, zone_id};
}

ZonedDateTime ZonedDateTime::from_instant(const Instant& instant, const std::string& zone_id)
{
    locate_zone_or_throw(zone_id);
    return ZonedDateTime{instant, zone_id};
}

Instant ZonedDateTime::instant() const
{
    return instant_;
}

std::string ZonedDateTime::zone_id() const
{
    return zone_id_;
}

CivilFields ZonedDateTime::fields() const
{
    const auto info = zone_info_for_instant(zone_id_, instant_.value_);
    const auto local_nanos = checked_add(
        instant_.value_.time_since_epoch().count(),
        checked_multiply(info.offset.count(), nanos_per_second));
    return fields_from_local(LocalTime{Nanoseconds{local_nanos}});
}

std::string ZonedDateTime::offset_string() const
{
    const auto offset = zone_info_for_instant(zone_id_, instant_.value_).offset;
    auto total_seconds = offset.count();
    const char sign = total_seconds < 0 ? '-' : '+';
    if (total_seconds < 0)
    {
        total_seconds = -total_seconds;
    }

    std::ostringstream out;
    out << sign << std::setw(2) << std::setfill('0') << (total_seconds / 3600)
        << ':' << std::setw(2) << ((total_seconds % 3600) / 60);
    return out.str();
}

std::string ZonedDateTime::to_string() const
{
    return format_civil(fields()) + offset_string() + '[' + zone_id_ + ']';
}

Clock::Clock(bool fixed, const Instant& instant)
    : fixed_(fixed)
    , instant_(instant)
{
}

Clock Clock::system()
{
    return Clock{false, Instant::from_unix(0, 0)};
}

Clock Clock::fixed(const Instant& instant)
{
    return Clock{true, instant};
}

Instant Clock::now() const
{
    if (fixed_)
    {
        return instant_;
    }

    return Instant{date::floor<Nanoseconds>(std::chrono::system_clock::now())};
}

Disambiguation parse_disambiguation(const std::string& value)
{
    if (value == "reject")
    {
        return Disambiguation::Reject;
    }
    if (value == "earliest")
    {
        return Disambiguation::Earliest;
    }
    if (value == "latest")
    {
        return Disambiguation::Latest;
    }
    throw std::invalid_argument("invalid temporal disambiguation");
}

std::string tzdb_version()
{
    try
    {
        return date::get_tzdb().version;
    }
    catch (const std::runtime_error& ex)
    {
        throw std::runtime_error(std::string("temporal timezone database unavailable: ") + ex.what());
    }
}

} // namespace space::temporal
