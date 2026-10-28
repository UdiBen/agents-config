#!/usr/bin/env python3
"""Turn a verifier's verified.json into the rolling blind-review report.

  build_report.py prev  --env RUN/env.sh [--prev FILE]
      Read the previous report (artifact HTML saved by the Artifact read action, or a
      Markdown fallback file), write RUN/prev.json with its latest findings, and print
      the next iteration number.

  build_report.py build --env RUN/env.sh [--prev FILE] --roster LIST [--skipped TEXT]
                        [--models TEXT] [--verify-cmd CMD] [--single-context] [--md]
      Append RUN/verified.json as the next iteration and write RUN/report.html, or with
      --md, INDEX_DIR/<slug>-r<N>.md. Prints the written path.

Tags and the verdict are derived here, so the orchestrator never judges a finding.
"""
import argparse
import datetime
import html
import json
import pathlib
import re
import shlex
import sys

SKILL_DIR = pathlib.Path(__file__).resolve().parent.parent
TEMPLATE = SKILL_DIR / "reference" / "report.html"
DATA_RE = re.compile(
    r'<script type="application/json" id="review-data">(.*?)</script>'
    r"|<!-- review-data\n(.*?)\n-->",
    re.S,
)
SEVERITIES = ["CRITICAL", "HIGH", "MEDIUM"]


def load_env(path):
    env = {}
    for line in pathlib.Path(path).read_text().splitlines():
        key, _, value = line.partition("=")
        if key:
            parts = shlex.split(value)
            env[key] = parts[0] if parts else ""
    return env


def load_prev(path):
    if not path:
        return None
    text = pathlib.Path(path).read_text()
    m = DATA_RE.search(text)
    if not m:
        sys.exit(f"build_report: no review data found in {path}")
    return json.loads(m.group(1) if m.group(1) is not None else m.group(2))


def field(finding, label):
    for name, text in finding.get("fields", []):
        if name.lower() == label.lower():
            return text.strip()
    return ""


def tag(finding):
    if finding.get("disputed"):
        return "disputed"
    if finding["kind"] == "CONTRACT":
        return "needs decision"
    if finding["kind"] == "SIMPLIFY" and field(finding, "Costs").lower().rstrip(".") != "nothing":
        return "needs decision"
    if finding.get("verdict") == "PLAUSIBLE":
        return "confirm first"
    return "mechanical"


def verdict(findings):
    present = {f["severity"] for f in findings}
    if "CRITICAL" in present:
        return "blocked"
    if "HIGH" in present:
        return "needs changes"
    if "MEDIUM" in present:
        return "ship with nits"
    return "ship"


def cmd_prev(args):
    env = load_env(args.env)
    data = load_prev(args.prev)
    run = pathlib.Path(env["RUN"])
    if not data:
        (run / "prev.json").write_text("[]")
        print(1)
        return
    latest = data["iterations"][-1]
    (run / "prev.json").write_text(json.dumps(latest["findings"], indent=1))
    print(len(data["iterations"]) + 1)


def to_markdown(data):
    it = data["iterations"][-1]
    out = [
        "<!-- review-data",
        json.dumps(data).replace("-->", "--\\u003e"),
        "-->",
        f"# {data['slug']} review — r{it['n']}",
        f"Reviewed: {it['head'][:12]} ({it['tree']}) against {it['base_ref']} "
        f"({it['base'][:12]}) on {it['date']}",
        f"Roster: {it['roster']}" + (f" · skipped: {it['skipped']}" if it["skipped"] else ""),
        f"Verdict: {it['verdict']} — {it.get('verdict_note', '')}",
    ]
    if it.get("single_context"):
        out.append("Single-context review: the bias this skill exists to remove was not removed.")

    def section(title, rows):
        if rows:
            out.extend(["", f"## {title}", *rows])

    section("Prior findings", [f"- {p['fate']} — {p['id']} — {p.get('note', '')}" for p in it["prior"]])
    section("Fix together", [f"- {', '.join(g['ids'])} — {g.get('note', '')}" for g in it["fix_together"]])
    rows = []
    for f in it["findings"]:
        settled = " · settled question" if f.get("from_question") else ""
        rows += ["", f"### [{f['tag']}] {f['kind']}: {f['title']} ({f['id']}){settled}",
                 f"File: {f['file']}:{f['line']} · Severity: {f['severity']} · "
                 f"Verified: {f['verdict']} — {f.get('verified', '')}",
                 f"Raised by: {', '.join(f.get('raised_by', []))}"]
        rows += [f"{name}: {text}" for name, text in f.get("fields", [])]
        if f.get("disputed"):
            rows.append(f"Disputed: {f['disputed']}")
    section("Findings", rows)
    section("Open questions", [f"- {q['file']}:{q['line']} — {q['title']}: {q['text']}"
                               + (f" Settled by: {q['needs']}" if q.get("needs") else "") for q in it["questions"]])
    section("Refuted by verifier", [f"- {r['file']}:{r['line']} — {r['title']}: {r['reason']}" for r in it["refuted"]])
    section("Nits", [f"- {n['file']}:{n['line']} — {n['text']} ({n.get('agent', '')})" for n in it["nits"]])
    section("Pre-existing", [f"- {p['file']}:{p['line']} — {p['text']}" for p in it["pre_existing"]])
    section("Checked and clear", [f"- {c}" for c in it["checked_clear"]])
    return "\n".join(out) + "\n"


def cmd_build(args):
    env = load_env(args.env)
    run = pathlib.Path(env["RUN"])
    new = json.loads((run / "verified.json").read_text())
    data = load_prev(args.prev) or {"repo": env["NWO"], "slug": env["SLUG"], "iterations": []}
    findings = new.get("findings", [])
    order = {s: i for i, s in enumerate(SEVERITIES)}
    findings.sort(key=lambda f: order.get(f["severity"], len(order)))
    for f in findings:
        f["tag"] = tag(f)
    iteration = {
        "n": len(data["iterations"]) + 1,
        "date": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
        "target": env["TARGET"],
        "head": env["HEAD_SHA"],
        "base_ref": env["BASE_REF"],
        "base": env["BASE"],
        "tree": env["TREE"],
        "roster": args.roster,
        "skipped": args.skipped or "",
        "models": args.models or "",
        "verify_cmd": args.verify_cmd or "",
        "single_context": args.single_context,
        "verdict": verdict(findings),
        "verdict_note": new.get("verdict_note", ""),
        "findings": findings,
    }
    for key in ("prior", "fix_together", "questions", "refuted", "nits", "pre_existing", "checked_clear"):
        iteration[key] = new.get(key, [])
    if "batch" in new:
        iteration["batch"] = new["batch"]
    data["iterations"].append(iteration)

    if args.md:
        index = pathlib.Path(env["INDEX_DIR"])
        index.mkdir(parents=True, exist_ok=True)
        out = index / f"{env['SLUG']}-r{iteration['n']}.md"
        out.write_text(to_markdown(data))
    else:
        page = TEMPLATE.read_text()
        payload = json.dumps(data).replace("</", "<\\/")
        page = page.replace("__TITLE__", html.escape(f"{env['SLUG']} review"), 1)
        page = page.replace("__DATA__", payload, 1)
        out = run / "report.html"
        out.write_text(page)
    print(out)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("prev")
    p.add_argument("--env", required=True)
    p.add_argument("--prev")
    b = sub.add_parser("build")
    b.add_argument("--env", required=True)
    b.add_argument("--prev")
    b.add_argument("--roster", required=True)
    b.add_argument("--skipped")
    b.add_argument("--models")
    b.add_argument("--verify-cmd")
    b.add_argument("--single-context", action="store_true")
    b.add_argument("--md", action="store_true")
    args = ap.parse_args()
    {"prev": cmd_prev, "build": cmd_build}[args.cmd](args)


if __name__ == "__main__":
    main()
