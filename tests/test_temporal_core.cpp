#include "temporal.h"

#include <cstdlib>
#include <exception>
#include <functional>
#include <iostream>
#include <stdexcept>
#include <string>

namespace
{
using namespace space::temporal;

void expect_true(bool value, const std::string& message)
{
    if (!value)
    {
        throw std::runtime_error(message);
    }
}

template <typename T, typename U>
void expect_eq(const T& actual, const U& expected)
{
    if (!(actual == expected))
    {
        throw std::runtime_error("expected equality");
    }
}

template <typename Fn>
void expect_throws(Fn&& fn)
{
    try
    {
        fn();
    }
    catch (const std::exception&)
    {
        return;
    }

    throw std::runtime_error("expected exception");
}

void test_instant_parse_format_requires_offset()
{
    expect_eq(Instant::parse("2026-09-25T12:34:56Z").to_string(),
              std::string("2026-09-25T12:34:56Z"));
    expect_eq(Instant::parse("2026-09-25T08:34:56-04:00").to_string(),
              std::string("2026-09-25T12:34:56Z"));
    expect_throws([] { Instant::parse("2026-09-25T12:34:56"); });
}

void test_instant_rejects_leap_second()
{
    expect_throws([] { Instant::parse("2026-12-31T23:59:60Z"); });
}

void test_duration_arithmetic_and_overflow()
{
    expect_eq(Duration::from_nanoseconds(1).to_string(), std::string("1ns"));
    expect_eq(Duration::from_seconds(90).to_string(), std::string("90000000000ns"));
    expect_eq(Duration::from_seconds(-90).to_string(), std::string("-90000000000ns"));

    expect_eq(Instant::parse("2026-09-25T12:34:56Z")
                  .add(Duration::from_parts(90, 500, 0, 0))
                  .to_string(),
              std::string("2026-09-25T12:36:26.5Z"));
    expect_throws([] {
        Instant::from_unix(9223372036LL, 854775807)
            .add(Duration::from_nanoseconds(1));
    });
}

void test_temporal_value_comparison()
{
    const auto one = Duration::from_seconds(1);
    const auto two = Duration::from_seconds(2);
    expect_eq(one.compare(two), -1);
    expect_eq(two.compare(one), 1);
    expect_eq(one.compare(Duration::from_seconds(1)), 0);

    const auto first = Instant::parse("2026-09-25T12:00:00Z");
    const auto second = Instant::parse("2026-09-25T12:00:01Z");
    expect_eq(first.compare(second), -1);
    expect_eq(second.compare(first), 1);
    expect_eq(first.compare(Instant::parse("2026-09-25T12:00:00Z")), 0);

    const auto plain = PlainDateTime::parse("2026-09-25T12:00:00");
    const auto later = PlainDateTime::parse("2026-09-25T12:00:01");
    expect_eq(plain.compare(later), -1);
    expect_eq(later.compare(plain), 1);
    expect_eq(plain.compare(PlainDateTime::parse("2026-09-25T12:00:00")), 0);
}

void test_plain_date_time_exact_duration_math()
{
    const auto start = PlainDateTime::parse("2026-09-25T12:00:00");
    const auto shifted = start.add(Duration::from_seconds(90));
    expect_eq(shifted.to_string(), std::string("2026-09-25T12:01:30"));
    expect_eq(shifted.since(start).compare(Duration::from_seconds(90)), 0);
    expect_eq(start.since(shifted).compare(Duration::from_seconds(-90)), 0);
    expect_throws([] {
        PlainDateTime::parse("2262-04-11T23:47:16.854775807")
            .add(Duration::from_nanoseconds(1));
    });
    expect_throws([] {
        PlainDateTime::parse("2262-04-11T23:47:16.854775807")
            .since(PlainDateTime::parse("1677-09-21T00:12:43.145224192"));
    });
}

void test_nanosecond_time_point_range_boundaries()
{
    expect_eq(Instant::parse("2262-04-11T23:47:16.854775807Z").to_string(),
              std::string("2262-04-11T23:47:16.854775807Z"));
    expect_eq(Instant::parse("1677-09-21T00:12:43.145224192Z").to_string(),
              std::string("1677-09-21T00:12:43.145224192Z"));
    expect_eq(Instant::parse("2262-04-12T00:47:16.854775807+01:00").to_string(),
              std::string("2262-04-11T23:47:16.854775807Z"));
    expect_eq(Instant::parse("1677-09-20T23:12:43.145224192-01:00").to_string(),
              std::string("1677-09-21T00:12:43.145224192Z"));
    expect_throws([] { Instant::parse("2262-04-11T23:47:16.854775808Z"); });
    expect_throws([] { Instant::parse("1677-09-21T00:12:43.145224191Z"); });
    expect_throws([] { Instant::parse("2262-04-12T00:47:16.854775808+01:00"); });
    expect_eq(PlainDateTime::parse("2262-04-11T23:47:16.854775807").to_string(),
              std::string("2262-04-11T23:47:16.854775807"));
    expect_eq(PlainDateTime::parse("1677-09-21T00:12:43.145224192").to_string(),
              std::string("1677-09-21T00:12:43.145224192"));
    expect_throws([] { PlainDateTime::parse("2262-04-11T23:47:16.854775808"); });
    expect_throws([] { PlainDateTime::from_fields(1677, 9, 21, 0, 12, 43, 145224191); });
    expect_throws([] { PlainDateTime::from_fields(67562, 9, 25, 12, 34, 56, 0); });
    expect_throws([] { PlainDateTime::from_fields(-67562, 9, 25, 12, 34, 56, 0); });
}

void test_from_unix_accepts_lower_boundary_parts()
{
    expect_eq(Instant::from_unix(-9223372037LL, 145224192).to_string(),
              std::string("1677-09-21T00:12:43.145224192Z"));
    expect_throws([] { Instant::from_unix(-9223372037LL, 145224191); });
}

void test_plain_date_time_field_validation()
{
    expect_throws([] { PlainDateTime::parse("2026-02-29T00:00:00"); });
    expect_throws([] { PlainDateTime::from_fields(2026, 13, 1, 0, 0, 0, 0); });
    expect_throws([] { PlainDateTime::from_fields(2026, 1, 1, 24, 0, 0, 0); });
}

void test_plain_date_time_add_days()
{
    expect_eq(PlainDateTime::parse("2028-02-28T10:11:12")
                  .add_days(1)
                  .to_string(),
              std::string("2028-02-29T10:11:12"));
    expect_eq(PlainDateTime::parse("2026-12-31T23:00:00")
                  .add_days(1)
                  .to_string(),
              std::string("2027-01-01T23:00:00"));
    expect_eq(PlainDateTime::parse("2026-01-01T00:00:00")
                  .add_days(-1)
                  .to_string(),
              std::string("2025-12-31T00:00:00"));
}

void test_plain_date_time_iso_weekday()
{
    expect_eq(PlainDateTime::parse("2026-09-28T00:00:00").iso_weekday(), 1);
    expect_eq(PlainDateTime::parse("2026-10-04T00:00:00").iso_weekday(), 7);
}

void test_zoned_from_plain_requires_valid_zone()
{
    expect_throws([] {
        ZonedDateTime::from_plain(PlainDateTime::parse("2026-01-01T00:00:00"),
                                  "Mars/Base",
                                  Disambiguation::Reject);
    });
}

void test_new_york_spring_gap_disambiguation()
{
    expect_throws([] {
        ZonedDateTime::from_plain(PlainDateTime::parse("2026-03-08T02:30:00"),
                                  "America/New_York",
                                  Disambiguation::Reject);
    });
    expect_eq(ZonedDateTime::from_plain(PlainDateTime::parse("2026-03-08T02:30:00"),
                                        "America/New_York",
                                        Disambiguation::Earliest)
                  .instant()
                  .to_string(),
              std::string("2026-03-08T07:00:00Z"));
    expect_eq(ZonedDateTime::from_plain(PlainDateTime::parse("2026-03-08T02:30:00"),
                                        "America/New_York",
                                        Disambiguation::Latest)
                  .instant()
                  .to_string(),
              std::string("2026-03-08T06:59:59.999999999Z"));
}

void test_new_york_fall_overlap_disambiguation()
{
    expect_eq(ZonedDateTime::from_plain(PlainDateTime::parse("2026-11-01T01:30:00"),
                                        "America/New_York",
                                        Disambiguation::Earliest)
                  .instant()
                  .to_string(),
              std::string("2026-11-01T05:30:00Z"));
    expect_eq(ZonedDateTime::from_plain(PlainDateTime::parse("2026-11-01T01:30:00"),
                                        "America/New_York",
                                        Disambiguation::Latest)
                  .instant()
                  .to_string(),
              std::string("2026-11-01T06:30:00Z"));
    expect_throws([] {
        ZonedDateTime::from_plain(PlainDateTime::parse("2026-11-01T01:30:00"),
                                  "America/New_York",
                                  Disambiguation::Reject);
    });
}

void test_fixed_clock_is_deterministic()
{
    expect_eq(Clock::fixed(Instant::parse("2026-09-25T12:34:56Z")).now().to_string(),
              std::string("2026-09-25T12:34:56Z"));
}

void test_tzdb_version_is_available()
{
    expect_true(!tzdb_version().empty(), "tzdb version should not be empty");
}

void run(const std::string& name, const std::function<void()>& test)
{
    test();
    std::cout << "PASS " << name << '\n';
}
}

int main()
{
    try
    {
        run("test_instant_parse_format_requires_offset", test_instant_parse_format_requires_offset);
        run("test_instant_rejects_leap_second", test_instant_rejects_leap_second);
        run("test_duration_arithmetic_and_overflow", test_duration_arithmetic_and_overflow);
        run("test_temporal_value_comparison", test_temporal_value_comparison);
        run("test_plain_date_time_exact_duration_math", test_plain_date_time_exact_duration_math);
        run("test_nanosecond_time_point_range_boundaries", test_nanosecond_time_point_range_boundaries);
        run("test_from_unix_accepts_lower_boundary_parts", test_from_unix_accepts_lower_boundary_parts);
        run("test_plain_date_time_field_validation", test_plain_date_time_field_validation);
        run("test_plain_date_time_add_days", test_plain_date_time_add_days);
        run("test_plain_date_time_iso_weekday", test_plain_date_time_iso_weekday);
        run("test_zoned_from_plain_requires_valid_zone", test_zoned_from_plain_requires_valid_zone);
        run("test_new_york_spring_gap_disambiguation", test_new_york_spring_gap_disambiguation);
        run("test_new_york_fall_overlap_disambiguation", test_new_york_fall_overlap_disambiguation);
        run("test_fixed_clock_is_deterministic", test_fixed_clock_is_deterministic);
        run("test_tzdb_version_is_available", test_tzdb_version_is_available);
    }
    catch (const std::exception& ex)
    {
        std::cerr << "FAIL: " << ex.what() << '\n';
        return EXIT_FAILURE;
    }

    return EXIT_SUCCESS;
}
