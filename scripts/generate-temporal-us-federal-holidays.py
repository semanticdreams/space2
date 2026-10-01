#!/usr/bin/env python3
from __future__ import annotations

import argparse
import calendar
import json
from datetime import date, timedelta
from pathlib import Path


PROVIDER_ID = "space.temporal.us-federal-holidays"
JURISDICTION = "US-FED"
WEEKEND_ISO_WEEKDAYS = [6, 7]


def nth_weekday(year: int, month: int, weekday: int, n: int) -> date:
    current = date(year, month, 1)
    while current.weekday() != weekday:
        current += timedelta(days=1)
    return current + timedelta(days=7 * (n - 1))


def last_weekday(year: int, month: int, weekday: int) -> date:
    current = date(year, month, calendar.monthrange(year, month)[1])
    while current.weekday() != weekday:
        current -= timedelta(days=1)
    return current


def observed_date(actual: date) -> date:
    if actual.weekday() == 5:
        return actual - timedelta(days=1)
    if actual.weekday() == 6:
        return actual + timedelta(days=1)
    return actual


def record(identifier: str, name: str, actual: date) -> dict:
    observed = observed_date(actual)
    return {
        "id": identifier,
        "name": name,
        "date": actual.isoformat(),
        "observed_date": observed.isoformat(),
        "observed": observed != actual,
    }


def holidays_for_year(year: int) -> list[dict]:
    records = [
        record("new-years-day", "New Year's Day", date(year, 1, 1)),
        record("martin-luther-king-jr-day", "Birthday of Martin Luther King, Jr.", nth_weekday(year, 1, 0, 3)),
        record("washingtons-birthday", "Washington's Birthday", nth_weekday(year, 2, 0, 3)),
        record("memorial-day", "Memorial Day", last_weekday(year, 5, 0)),
        record("juneteenth-national-independence-day", "Juneteenth National Independence Day", date(year, 6, 19)),
        record("independence-day", "Independence Day", date(year, 7, 4)),
        record("labor-day", "Labor Day", nth_weekday(year, 9, 0, 1)),
        record("columbus-day", "Columbus Day", nth_weekday(year, 10, 0, 2)),
        record("veterans-day", "Veterans Day", date(year, 11, 11)),
        record("thanksgiving-day", "Thanksgiving Day", nth_weekday(year, 11, 3, 4)),
        record("christmas-day", "Christmas Day", date(year, 12, 25)),
    ]
    return sorted(records, key=lambda item: item["observed_date"])


def build_seed(start_year: int, end_year: int) -> dict:
    if start_year != 2026 or end_year != 2027:
        raise ValueError("only the deterministic US-FED 2026-2027 seed range is supported")
    years: dict[str, list[dict]] = {}
    for observed_year in range(start_year, end_year + 1):
        records: list[dict] = []
        for statutory_year in range(observed_year - 1, observed_year + 2):
            for item in holidays_for_year(statutory_year):
                if item["observed_date"].startswith(f"{observed_year:04d}-"):
                    records.append(item)
        years[str(observed_year)] = sorted(records, key=lambda item: item["observed_date"])
    return {
        "schema_version": 1,
        "provider_id": PROVIDER_ID,
        "jurisdiction_order": [JURISDICTION],
        "year_start": start_year,
        "year_end": end_year,
        "weekend_iso_weekdays": WEEKEND_ISO_WEEKDAYS,
        "jurisdictions": {
            JURISDICTION: {
                "name": "United States federal holidays",
                "years": years,
            }
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate deterministic US-FED temporal holiday seed data")
    parser.add_argument("--start-year", type=int, required=True)
    parser.add_argument("--end-year", type=int, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    seed = build_seed(args.start_year, args.end_year)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(seed, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
