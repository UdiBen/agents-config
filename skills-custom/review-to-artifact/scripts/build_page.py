#!/usr/bin/env python3
"""Build the review page for one branch from its blind-review rounds.

  build_page.py --hist <HIST_DIR> --out <page.html>

Reads every HIST_DIR/r<N>.json in round order, fills reference/page.html, and prints the
output path.
"""
import argparse
import html
import json
import pathlib
import re
import sys

TEMPLATE = pathlib.Path(__file__).resolve().parent.parent / "reference" / "page.html"


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--hist", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()
    hist = pathlib.Path(args.hist)
    found = sorted(
        (int(m.group(1)), p) for p in hist.glob("r*.json") if (m := re.fullmatch(r"r(\d+)\.json", p.name))
    )
    if not found:
        sys.exit(f"build_page: no rounds in {hist}")
    rounds = [json.loads(p.read_text()) for _, p in found]
    latest = rounds[-1]
    data = {"repo": latest["repo"], "slug": latest["slug"], "iterations": rounds}
    page = TEMPLATE.read_text()
    page = page.replace("__TITLE__", html.escape(f"{latest['slug']} review"), 1)
    page = page.replace("__DATA__", json.dumps(data).replace("</", "<\\/"), 1)
    out = pathlib.Path(args.out)
    out.write_text(page)
    print(out)


if __name__ == "__main__":
    main()
