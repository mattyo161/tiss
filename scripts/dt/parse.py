#!/usr/bin/env python3
#
# @description Parse almost any date/time string into epoch/ISO/compact forms
# @usage tiss dt parse [--epoch|--iso|--ts] <date string...>
# @example tiss dt parse 12/24/26 9:00 PM
# @example tiss dt parse --epoch "Mon 12/24/28"
# @example cat dates.txt | tiss dt parse
#
# The tiss date brain. Tries a battery of formats (ISO, epoch, US styles,
# month names, the tiss compact form) with inference rules for what's
# missing:
#   - two-digit years: 00-30 -> 2000s, 31-99 -> 1900s
#   - ...unless a weekday is given, in which case the century that makes
#     the weekday true wins ("Mon 12/24/28" -> 1928, a Monday)
#   - missing year: the candidate closest to now wins ("12/24" in January
#     -> last month, not eleven months from now)
#
# Output is jsonl: {"input", "epoch", "iso", "ts"} — epoch is UTC seconds,
# iso is UTC, ts is the local compact form. --epoch/--iso/--ts print just
# that field. Args are joined (no quoting needed); with no args, parses
# one input per stdin line. Naive inputs are interpreted as local time.
#
import json
import sys
from datetime import datetime, timezone

# --- format matrix -------------------------------------------------------------
DATE_FMTS = [
    # (strptime fragment, has_year, two_digit_year)
    ("%Y-%m-%d", True, False),
    ("%Y/%m/%d", True, False),
    ("%Y%m%d", True, False),
    ("%m/%d/%Y", True, False),
    ("%m-%d-%Y", True, False),
    ("%d %b %Y", True, False),
    ("%d %B %Y", True, False),
    ("%b %d %Y", True, False),
    ("%B %d %Y", True, False),
    ("%m/%d/%y", True, True),
    ("%m-%d-%y", True, True),
    ("%m/%d", False, False),
    ("%m-%d", False, False),
    ("%b %d", False, False),
    ("%B %d", False, False),
    ("%d %b", False, False),
]
TIME_FMTS = ["", "%H:%M:%S", "%H:%M", "%I:%M:%S %p", "%I:%M %p", "%I %p"]
WEEKDAYS = "monday tuesday wednesday thursday friday saturday sunday".split()


def normalize(text):
    text = " ".join(text.replace(",", " ").split())
    return text


def split_weekday(text):
    """Peel a leading weekday name off; return (weekday_index_or_None, rest)."""
    parts = text.split(None, 1)
    if len(parts) == 2:
        head = parts[0].lower().rstrip(".")
        for i, day in enumerate(WEEKDAYS):
            if head == day or (len(head) >= 3 and day.startswith(head)):
                return i, parts[1]
    return None, text


def century_candidates(two_digit_year):
    """Matt's rule first (00-30 -> 2000s), then the other century."""
    if two_digit_year <= 30:
        return [2000 + two_digit_year, 1900 + two_digit_year]
    return [1900 + two_digit_year, 2000 + two_digit_year]


def nearest_year_candidates(now):
    return [now.year - 1, now.year, now.year + 1]


def try_parse(text, now):
    """Return (datetime, notes) or None. Naive result = local wall time."""
    raw = normalize(text)

    # Bare epoch (seconds or milliseconds).
    stripped = raw.lstrip("-")
    if stripped.isdigit() and len(stripped) >= 9:
        val = int(raw)
        if len(stripped) >= 13:
            val //= 1000
        return datetime.fromtimestamp(val), {}

    # ISO 8601 (python handles offsets; map Z explicitly for < 3.11 safety).
    try:
        dt = datetime.fromisoformat(raw.replace("Z", "+00:00"))
        return dt, {}
    except ValueError:
        pass

    # tiss compact form.
    try:
        return datetime.strptime(raw, "%Y%m%dT%H%M%S"), {}
    except ValueError:
        pass

    weekday, rest = split_weekday(raw)

    for date_fmt, has_year, two_digit in DATE_FMTS:
        for time_fmt in TIME_FMTS:
            fmt = (date_fmt + " " + time_fmt).strip()
            try:
                if has_year:
                    dt = datetime.strptime(rest, fmt)
                else:
                    # Inject a leap year so Feb 29 parses and python's
                    # no-year strptime deprecation stays quiet; real year
                    # candidates replace it below.
                    dt = datetime.strptime("2000 " + rest, "%Y " + fmt)
            except ValueError:
                continue

            if not has_year:
                # Missing year: candidates around now; weekday filters,
                # otherwise closest-to-now wins.
                cands = []
                for y in nearest_year_candidates(now):
                    try:
                        cands.append(dt.replace(year=y))
                    except ValueError:
                        continue  # e.g. Feb 29 in a non-leap year
                if weekday is not None:
                    matching = [c for c in cands if c.weekday() == weekday]
                    if matching:
                        cands = matching
                if not cands:
                    continue
                best = min(cands, key=lambda c: abs(c - now))
                return best, {}

            if two_digit:
                yy = dt.year % 100
                cands = century_candidates(yy)
                if weekday is not None:
                    for y in cands:
                        c = dt.replace(year=y)
                        if c.weekday() == weekday:
                            return c, {}
                return dt.replace(year=cands[0]), {}

            notes = {}
            if weekday is not None and dt.weekday() != weekday:
                notes["weekday_mismatch"] = True
            return dt, notes
    return None


def render(dt, notes, text, mode):
    if dt.tzinfo is None:
        local = dt
        # astimezone() attaches the local tz; timestamp() then handles any
        # era, including pre-1970 (mktime overflows on those).
        epoch = int(dt.astimezone().timestamp())
    else:
        epoch = int(dt.timestamp())
        local = datetime.fromtimestamp(epoch)
    iso = datetime.fromtimestamp(epoch, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    ts = local.strftime("%Y%m%dT%H%M%S")
    if mode == "epoch":
        return str(epoch)
    if mode == "iso":
        return iso
    if mode == "ts":
        return ts
    out = {"input": text, "epoch": epoch, "iso": iso, "ts": ts}
    out.update(notes)
    return json.dumps(out)


def main():
    args = sys.argv[1:]
    mode = "json"
    now = datetime.now()

    while args and args[0].startswith("--"):
        flag = args.pop(0)
        if flag in ("--epoch", "--iso", "--ts"):
            mode = flag[2:]
        elif flag == "--now":  # deterministic reference, mainly for tests
            now = datetime.fromtimestamp(int(args.pop(0)))
        elif flag == "--help":
            print("usage: tiss dt parse [--epoch|--iso|--ts] <date string...>", file=sys.stderr)
            sys.exit(0)
        else:
            print(f"dt parse: unknown option {flag}", file=sys.stderr)
            sys.exit(2)

    inputs = [" ".join(args)] if args else [ln.strip() for ln in sys.stdin if ln.strip()]
    if not inputs or not inputs[0]:
        print("usage: tiss dt parse [--epoch|--iso|--ts] <date string...>", file=sys.stderr)
        sys.exit(2)

    status = 0
    for text in inputs:
        result = try_parse(text, now)
        if result is None:
            print(f"dt parse: could not parse '{text}'", file=sys.stderr)
            status = 1
            continue
        dt, notes = result
        print(render(dt, notes, text, mode))
    sys.exit(status)


if __name__ == "__main__":
    main()
