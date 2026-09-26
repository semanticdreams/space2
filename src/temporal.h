#pragma once

#include <chrono>
#include <cstdint>
#include <string>

#include <date/date.h>

namespace space::temporal
{

enum class Disambiguation { Reject, Earliest, Latest };

struct CivilFields
{
    int year;
    int month;
    int day;
    int hour;
    int minute;
    int second;
    int nanosecond;
};

class Duration
{
public:
    static Duration from_nanoseconds(std::int64_t nanoseconds);
    static Duration from_seconds(std::int64_t seconds);
    static Duration from_parts(std::int64_t seconds,
                               std::int64_t milliseconds,
                               std::int64_t microseconds,
                               std::int64_t nanoseconds);
    int compare(const Duration& other) const;
    std::int64_t nanoseconds() const;
    std::string to_string() const;

private:
    explicit Duration(std::chrono::nanoseconds value);

    std::chrono::nanoseconds value_{};

    friend class Instant;
    friend class PlainDateTime;
};

class Instant
{
public:
    static Instant parse(const std::string& text);
    static Instant from_unix(std::int64_t epoch_seconds, std::int32_t nanosecond);
    std::int64_t epoch_seconds() const;
    std::int32_t nanosecond() const;
    std::string to_string() const;
    int compare(const Instant& other) const;
    Instant add(const Duration& duration) const;
    Duration since(const Instant& earlier) const;
    bool operator==(const Instant& other) const;
    bool operator<(const Instant& other) const;

private:
    explicit Instant(date::sys_time<std::chrono::nanoseconds> value);

    date::sys_time<std::chrono::nanoseconds> value_{};

    friend class ZonedDateTime;
    friend class Clock;
};

class PlainDateTime
{
public:
    static PlainDateTime parse(const std::string& text);
    static PlainDateTime from_fields(int year,
                                     int month,
                                     int day,
                                     int hour,
                                     int minute,
                                     int second,
                                     int nanosecond);
    CivilFields fields() const;
    std::string to_string() const;
    int compare(const PlainDateTime& other) const;
    PlainDateTime add(const Duration& duration) const;
    Duration since(const PlainDateTime& earlier) const;
    PlainDateTime add_days(int days) const;
    int iso_weekday() const;

private:
    explicit PlainDateTime(date::local_time<std::chrono::nanoseconds> value);

    date::local_time<std::chrono::nanoseconds> value_{};

    friend class ZonedDateTime;
};

class ZonedDateTime
{
public:
    static ZonedDateTime from_plain(const PlainDateTime& local,
                                    const std::string& zone_id,
                                    Disambiguation disambiguation);
    static ZonedDateTime from_instant(const Instant& instant,
                                      const std::string& zone_id);
    Instant instant() const;
    std::string zone_id() const;
    CivilFields fields() const;
    std::string offset_string() const;
    std::string to_string() const;

private:
    ZonedDateTime(const Instant& instant, std::string zone_id);

    Instant instant_;
    std::string zone_id_;
};

class Clock
{
public:
    static Clock system();
    static Clock fixed(const Instant& instant);
    Instant now() const;

private:
    Clock(bool fixed, const Instant& instant);

    bool fixed_;
    Instant instant_;
};

Disambiguation parse_disambiguation(const std::string& value);
std::string tzdb_version();

}
