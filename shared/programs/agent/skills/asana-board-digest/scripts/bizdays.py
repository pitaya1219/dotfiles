#!/usr/bin/env python3
"""Business-day arithmetic for the board digest, in the board's timezone.

Two operations, both of which are easy to get subtly wrong by hand and are
therefore not left to the agent:

    cutoff [none|YYYY-MM-DD|Nd]   -> the window start as ISO8601 UTC
    elapsed <ISO8601 timestamp>   -> business days from then until today

The Asana search API takes UTC while the board is read in JST, so midnight JST
is 15:00Z of the *previous* day -- the single most likely off-by-one in the
whole skill, and the reason `cutoff` exists rather than a documented formula.

Saturday and Sunday are the only non-business days. Japanese public holidays
are deliberately not modelled: a holiday table is one more thing to maintain
and go stale, and the digest's own report says when a run follows a long break.
"""

import sys
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

BOARD_TZ = ZoneInfo("Asia/Tokyo")
SATURDAY = 5


def is_business_day(day):
    return day.weekday() < SATURDAY


def step_back_business_days(day, count):
    """The date `count` business days before `day` (0 returns `day` itself)."""
    for _ in range(count):
        day -= timedelta(days=1)
        while not is_business_day(day):
            day -= timedelta(days=1)
    return day


def to_utc_iso(day):
    """Midnight JST on `day`, as the UTC instant Asana's filters expect."""
    midnight = datetime(day.year, day.month, day.day, tzinfo=BOARD_TZ)
    return midnight.astimezone(ZoneInfo("UTC")).strftime("%Y-%m-%dT%H:%M:%SZ")


def cutoff(arg):
    today = datetime.now(BOARD_TZ).date()

    # An unset $ARGUMENTS still reaches us as an empty string, and that means
    # "no window given" exactly as much as no argument at all does.
    arg = arg.strip() if arg else None
    if not arg:
        return to_utc_iso(step_back_business_days(today, 1))

    if arg.endswith("d") and arg[:-1].isdigit():
        return to_utc_iso(step_back_business_days(today, int(arg[:-1])))

    try:
        return to_utc_iso(datetime.strptime(arg, "%Y-%m-%d").date())
    except ValueError:
        raise SystemExit(
            f"cutoff: cannot read {arg!r}. Expected nothing, YYYY-MM-DD, or Nd "
            f"(e.g. 3d for three business days ago)."
        )


def elapsed(timestamp):
    """Business days between `timestamp` and now, counted in board-local dates.

    Same JST date as today is 0. Both Asana timestamp shapes are accepted, with
    and without fractional seconds, because `modified_at` carries milliseconds
    and hand-typed arguments generally do not.
    """
    text = timestamp.replace("Z", "+00:00")
    try:
        then = datetime.fromisoformat(text).astimezone(BOARD_TZ).date()
    except ValueError:
        raise SystemExit(f"elapsed: cannot read {timestamp!r} as an ISO8601 timestamp.")

    today = datetime.now(BOARD_TZ).date()
    if then >= today:
        return 0

    days = 0
    day = then
    while day < today:
        day += timedelta(days=1)
        if is_business_day(day):
            days += 1
    return days


def main(argv):
    if len(argv) < 2:
        raise SystemExit(__doc__)

    command = argv[1]
    if command == "cutoff":
        print(cutoff(argv[2] if len(argv) > 2 else None))
    elif command == "elapsed":
        if len(argv) < 3:
            raise SystemExit("elapsed: needs an ISO8601 timestamp.")
        print(elapsed(argv[2]))
    else:
        raise SystemExit(f"unknown command {command!r}. Expected cutoff or elapsed.")


if __name__ == "__main__":
    main(sys.argv)
