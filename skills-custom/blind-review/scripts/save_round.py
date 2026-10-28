#!/usr/bin/env python3
"""Save a blind-review round to the branch's history directory.

  save_round.py prev --env RUN/env.sh
      Write RUN/prev.json with the latest round's findings, and print the next round number.

  save_round.py save --env RUN/env.sh --roster LIST [--skipped TEXT] [--models TEXT]
                     [--verify-cmd CMD] [--single-context]
      Read RUN/verified.json, derive tags and the verdict, and write HIST_DIR/r<N>.json and
      HIST_DIR/r<N>.md. Prints both paths.

A round record is the contract for delivery skills (review-to-artifact, review-to-difftool):
{repo, slug, n, date, target, head, base_ref, base, tree, roster, skipped, models,
 verify_cmd, single_context, verdict, verdict_note, prior, fix_together, findings,
 questions, refuted, nits, pre_existing, checked_clear[, batch]}.
"""
import argparse
import datetime
import json
import pathlib
import re
import shlex

SEVERITIES = ["CRITICAL", "HIGH", "MEDIUM"]


def load_env(path):
    env = {}
    for line in pathlib.Path(path).read_text().splitlines():
        key, _, value = line.partition("=")
        if key:
            parts = shlex.split(value)
            env[key] = parts[0] if parts else ""
    return env


def rounds(hist):
    found = []
    for p in hist.glob("r*.json"):
        m = re.fullmatch(r"r(\d+)\.json", p.name)
        if m:
            found.append((int(m.group(1)), p))
    return [p for _, p in sorted(found)]


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


def to_markdown(rec, prev):
    titles = {f["id"]: f["title"] for f in (prev or {}).get("findings", [])}
    out = [
        f"# {rec['slug']} review — r{rec['n']}",
        f"Reviewed: {rec['head'][:12]} ({rec['tree']}) against {rec['base_ref']} "
        f"({rec['base'][:12]}) on {rec['date']}",
        f"Roster: {rec['roster']}" + (f" · skipped: {rec['skipped']}" if rec["skipped"] else ""),
        f"Verdict: {rec['verdict']} — {rec.get('verdict_note', '')}",
    ]
    if rec.get("single_context"):
        out.append("Single-context review: the bias this skill exists to remove was not removed.")

    def section(title, rows):
        if rows:
            out.extend(["", f"## {title}", *rows])

    section("Prior findings", [f"- {p['fate']} — {p['id']} {titles.get(p['id'], '')} — {p.get('note', '')}"
                               for p in rec["prior"]])
    section("Fix together", [f"- {', '.join(g['ids'])} — {g.get('note', '')}" for g in rec["fix_together"]])
    rows = []
    for f in rec["findings"]:
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
                               + (f" Settled by: {q['needs']}" if q.get("needs") else "") for q in rec["questions"]])
    section("Refuted by verifier", [f"- {r['file']}:{r['line']} — {r['title']}: {r['reason']}" for r in rec["refuted"]])
    section("Nits", [f"- {n['file']}:{n['line']} — {n['text']} ({n.get('agent', '')})" for n in rec["nits"]])
    section("Pre-existing", [f"- {p['file']}:{p['line']} — {p['text']}" for p in rec["pre_existing"]])
    section("Checked and clear", [f"- {c}" for c in rec["checked_clear"]])
    return "\n".join(out) + "\n"


def cmd_prev(args):
    env = load_env(args.env)
    run, hist = pathlib.Path(env["RUN"]), pathlib.Path(env["HIST_DIR"])
    found = rounds(hist)
    if not found:
        (run / "prev.json").write_text("[]")
        print(1)
        return
    latest = json.loads(found[-1].read_text())
    (run / "prev.json").write_text(json.dumps(latest["findings"], indent=1))
    print(latest["n"] + 1)


def cmd_save(args):
    env = load_env(args.env)
    run, hist = pathlib.Path(env["RUN"]), pathlib.Path(env["HIST_DIR"])
    new = json.loads((run / "verified.json").read_text())
    found = rounds(hist)
    prev = json.loads(found[-1].read_text()) if found else None
    findings = new.get("findings", [])
    order = {s: i for i, s in enumerate(SEVERITIES)}
    findings.sort(key=lambda f: order.get(f["severity"], len(order)))
    for f in findings:
        f["tag"] = tag(f)
    rec = {
        "repo": env["NWO"],
        "slug": env["SLUG"],
        "n": (prev["n"] + 1) if prev else 1,
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
        rec[key] = new.get(key, [])
    if "batch" in new:
        rec["batch"] = new["batch"]
    hist.mkdir(parents=True, exist_ok=True)
    out = hist / f"r{rec['n']}.json"
    out.write_text(json.dumps(rec, indent=1))
    md = hist / f"r{rec['n']}.md"
    md.write_text(to_markdown(rec, prev))
    print(out)
    print(md)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("prev")
    p.add_argument("--env", required=True)
    s = sub.add_parser("save")
    s.add_argument("--env", required=True)
    s.add_argument("--roster", required=True)
    s.add_argument("--skipped")
    s.add_argument("--models")
    s.add_argument("--verify-cmd")
    s.add_argument("--single-context", action="store_true")
    args = ap.parse_args()
    {"prev": cmd_prev, "save": cmd_save}[args.cmd](args)


if __name__ == "__main__":
    main()
