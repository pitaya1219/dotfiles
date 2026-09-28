#!/usr/bin/env python3
"""Prune a local `file://` binary cache down to a size budget.

The cache is a flat directory of `<hash>.narinfo` files plus the `nar/` files
they point at, so the two have to be pruned together: a narinfo whose nar is
gone is worse than either kind of leftover, because the substituter goes on
advertising a path it can no longer serve and every build that asks for it
fails instead of falling back. Narinfos are therefore chosen first and the nar
sweep is driven by what survived, never by what was planned.

Retention is by closure rather than by individual path. A narinfo whose
`References` are missing from the cache still substitutes, but only by
fetching those references from somewhere else -- which for the machines this
runs on is nowhere, since each is the only one of its architecture here. Such
a path is present in the cache and still costs a rebuild, so keeping it is
keeping nothing.
"""

import argparse
import os
import sys
import time
from collections import deque
from pathlib import Path

SIZE_UNITS = {"": 1, "K": 10**3, "M": 10**6, "G": 10**9, "T": 10**12,
              "KIB": 2**10, "MIB": 2**20, "GIB": 2**30, "TIB": 2**40}


def parse_size(text):
    value = text.strip().upper()
    for suffix in sorted(SIZE_UNITS, key=len, reverse=True):
        if suffix and value.endswith(suffix):
            return int(float(value[: -len(suffix)]) * SIZE_UNITS[suffix])
    return int(float(value))


def human(n):
    for unit in ("B", "KiB", "MiB", "GiB", "TiB"):
        if abs(n) < 1024 or unit == "TiB":
            return f"{n:.2f}{unit}" if unit != "B" else f"{n}B"
        n /= 1024


class Entry:
    __slots__ = ("hash", "narinfo", "url", "size", "mtime", "refs")

    def __init__(self, hash_, narinfo, url, size, mtime, refs):
        self.hash = hash_
        self.narinfo = narinfo
        self.url = url
        self.size = size
        self.mtime = mtime
        self.refs = refs


def store_hash(basename):
    """The cache indexes by the store path's hash, which is its first component."""
    return basename.split("-", 1)[0]


def read_entries(cache_dir):
    """Parse every narinfo. Returns (entries by hash, unparseable narinfo paths)."""
    entries = {}
    broken = []
    for narinfo in cache_dir.glob("*.narinfo"):
        url = None
        size = None
        refs = set()
        try:
            with narinfo.open(encoding="utf-8", errors="replace") as handle:
                for line in handle:
                    key, _, value = line.partition(":")
                    value = value.strip()
                    if key == "URL":
                        url = value
                    elif key == "FileSize":
                        size = int(value)
                    elif key == "References":
                        refs = {store_hash(r) for r in value.split()}
            stat = narinfo.stat()
        except (OSError, ValueError):
            broken.append(narinfo)
            continue

        # No URL means nothing can be fetched through this narinfo anyway, and
        # keeping it would also hide which nar it was protecting.
        if url is None:
            broken.append(narinfo)
            continue

        if size is None:
            nar = cache_dir / url
            size = nar.stat().st_size if nar.exists() else 0

        hash_ = narinfo.stem
        entries[hash_] = Entry(hash_, narinfo, url, size, stat.st_mtime, refs)
    return entries, broken


def select(entries, budget):
    """Keep whole closures, newest push first, while they fit in the budget.

    A narinfo's mtime is when it was last pushed, not when it was last read
    back: a file cache records no access time we could trust. Push time is the
    right proxy regardless, since what the cache exists to save is the rebuild
    of something recently built.
    """
    order = sorted(entries.values(), key=lambda e: (e.mtime, e.hash), reverse=True)
    keep = set()
    kept_urls = set()
    kept_bytes = 0

    for root in order:
        if root.hash in keep:
            continue

        closure = set()
        queue = deque([root.hash])
        while queue:
            current = queue.popleft()
            if current in closure or current not in entries:
                continue
            closure.add(current)
            queue.extend(entries[current].refs)

        added = {entries[h].url for h in closure - keep} - kept_urls
        cost = sum(entries[h].size for h in closure - keep if entries[h].url in added)

        # An empty `keep` means this is the newest closure, and it is taken
        # whatever it costs: emptying the cache of the build that just finished
        # is a worse answer than briefly sitting over the cap. Later closures
        # that do not fit are skipped rather than ending the walk, so the
        # smaller ones behind an oversized one still get their chance.
        if keep and kept_bytes + cost > budget:
            continue

        keep |= closure
        kept_urls |= added
        kept_bytes += cost

    return keep, kept_bytes


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache-dir", required=True, type=Path)
    parser.add_argument("--max-size", required=True,
                        help="Size budget, e.g. 5GiB, 500M, or a plain byte count.")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    cache_dir = args.cache_dir
    budget = parse_size(args.max_size)

    # Every binary cache has this file and nothing else does, so requiring it
    # is what keeps a mistyped --cache-dir from deleting an unrelated tree.
    if not (cache_dir / "nix-cache-info").is_file():
        print(f"{cache_dir} has no nix-cache-info; not a binary cache, refusing to prune.",
              file=sys.stderr)
        return 1

    if not args.dry_run and not os.access(cache_dir, os.W_OK):
        print(f"{cache_dir} is not writable by this user; re-run under sudo.",
              file=sys.stderr)
        return 1

    # Everything below compares against this rather than against "now": the
    # post-build hook writes a nar before the narinfo that references it, so a
    # nar appearing after the scan began may still acquire a referrer, and
    # sweeping it would leave exactly the dangling narinfo this avoids.
    scan_start = time.time()

    entries, broken = read_entries(cache_dir)
    total = sum(e.size for e in entries.values())
    keep, kept_bytes = select(entries, budget)

    drop = [e for h, e in entries.items() if h not in keep]
    action = "would remove" if args.dry_run else "removed"

    if not args.dry_run:
        for entry in drop:
            entry.narinfo.unlink(missing_ok=True)
            # nix writes a listing beside the narinfo when write-nar-listing is
            # on; it is useless once the narinfo is gone.
            entry.narinfo.with_suffix(".ls").unlink(missing_ok=True)
        for narinfo in broken:
            narinfo.unlink(missing_ok=True)

    # Re-read rather than reuse `keep`: a push concurrent with this run has its
    # narinfo on disk but not in the scan above, and its nar must survive.
    live = cache_dir / "nar"
    if args.dry_run:
        referenced = {entries[h].url for h in keep}
    else:
        referenced = {e.url for e in read_entries(cache_dir)[0].values()}

    swept = 0
    swept_bytes = 0
    if live.is_dir():
        for nar in live.iterdir():
            rel = f"nar/{nar.name}"
            if rel in referenced:
                continue
            try:
                stat = nar.stat()
            except OSError:
                continue
            if stat.st_mtime >= scan_start:
                continue
            swept += 1
            swept_bytes += stat.st_size
            if not args.dry_run:
                nar.unlink(missing_ok=True)

    print(f"{cache_dir}: {len(entries)} paths, {human(total)} before; "
          f"budget {human(budget)}")
    if broken:
        print(f"  {action} {len(broken)} unreadable narinfo file(s)")
    print(f"  {action} {len(drop)} narinfo file(s), "
          f"kept {len(keep)} ({human(kept_bytes)})")
    print(f"  {action} {swept} unreferenced nar file(s) ({human(swept_bytes)})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
