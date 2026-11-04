#!/usr/bin/env python3
"""Save a blind-review round to the branch's history directory.

  save_round.py prev --env RUN/env.sh
      Write RUN/prev.json with the latest round's findings, and print the next round number.

  save_round.py save --env RUN/env.sh --roster LIST [--skipped TEXT] [--models TEXT]
                     [--verify-cmd CMD] [--single-context]
      Read RUN/verified.json, derive tags and the verdict, and write HIST_DIR/r<N>.json and
      HIST_DIR/r<N>.md. Prints both paths.

A round record is the contract every destination in reference/deliver.md reads:
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


CALLS = ["fix", "skip", "decide"]
VERIFIED = {"CONFIRMED": "yes", "PLAUSIBLE": "partly"}
LISTS = ["questions", "refuted", "nits", "pre_existing"]


def tag(finding):
    if finding.get("disputed") or finding["kind"] == "CONTRACT":
        return "decide"
    return finding.get("call") if finding.get("call") in CALLS else "decide"


def code_span(text):
    text = text.strip()
    fence = "``" if "`" in text else "`"
    pad = " " if fence == "``" else ""
    return f"{fence}{pad}{text}{pad}{fence}"


def ref(entry_id, n=None):
    if not isinstance(entry_id, int):
        return str(entry_id)
    return f"r{n} #{entry_id}" if n else f"#{entry_id}"


def number(rec):
    """Number every entry from 1 in report order; a finding keeps its key across rounds."""
    count = 0
    for f in rec["findings"]:
        count += 1
        f["key"] = f.get("key") or f.get("id") or f"r{rec['n']}-{count}"
        f["id"] = count
    for key in LISTS:
        for item in rec[key]:
            count += 1
            item["id"] = count
    ids = {f["key"]: f["id"] for f in rec["findings"]}
    for g in rec["fix_together"]:
        g["ids"] = [ids.get(k, k) for k in g.pop("keys", g.get("ids", []))]
    for p in rec["prior"]:
        p["key"] = p.get("key") or p.pop("id", "")


def disputed_rows(d):
    if isinstance(d, dict):
        return ["- Disputed:", f"  - For: {d.get('for', '')}", f"  - Against: {d.get('against', '')}"]
    return [f"- Disputed: {d}"] if d else []


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
    prev_findings = (prev or {}).get("findings", [])
    titles = {f.get("key") or f["id"]: f["title"] for f in prev_findings}
    prev_ids = {f.get("key") or f["id"]: f["id"] for f in prev_findings}
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

    section("Prior findings", [f"- {p['fate']} — {ref(prev_ids.get(p['key'], p['key']), prev and prev['n'])} "
                               f"{titles.get(p['key'], '')} — {p.get('note', '')}" for p in rec["prior"]])
    section("Fix together", [f"- {', '.join(ref(i) for i in g['ids'])} — {g.get('note', '')}"
                             for g in rec["fix_together"]])
    rows = []
    for f in rec["findings"]:
        rows += ["", f"### {ref(f['id'])} · {f['severity']} · {f['title']}",
                 f"{f['file']}:{f['line']} · found by: {', '.join(f.get('raised_by', []))}"]
        if f.get("summary"):
            rows += ["", f["summary"]]
        rows.append("")
        if f.get("evidence"):
            rows.append(f"- Code: {code_span(f['evidence'])}")
        if f.get("repro"):
            rows.append(f"- Repro: {f['repro']}")
        rows.append(f"- Verified: {VERIFIED.get(f['verdict'], f['verdict'])} — {f.get('verified', '')}")
        rows += disputed_rows(f.get("disputed"))
        rows.append(f"- Verdict: {f['tag']} — {f.get('how', '')}")
    section("Findings", rows)
    section("Open questions", [f"- {ref(q['id'])} · {q['file']}:{q['line']} — {q['title']}"
                               + (f" (settled by: {q['needs']})" if q.get("needs") else "") for q in rec["questions"]])
    section("Refuted", [f"- {ref(r['id'])} · {r['file']}:{r['line']} — {r['title']} — {r['reason']}" for r in rec["refuted"]])
    section("Nits", [f"- {ref(n['id'])} · {n['file']}:{n['line']} — {n['text']} ({n.get('agent', '')})" for n in rec["nits"]])
    section("Pre-existing", [f"- {ref(p['id'])} · {p['file']}:{p['line']} — {p['text']}" for p in rec["pre_existing"]])
    if rec["checked_clear"]:
        out.extend(["", f"Checked and clear: {len(rec['checked_clear'])} items, listed in r{rec['n']}.json"])
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
    for f in latest["findings"]:
        f["key"] = f.get("key") or f["id"]
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
    number(rec)
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
