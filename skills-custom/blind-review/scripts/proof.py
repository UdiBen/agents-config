#!/usr/bin/env python3
"""Split a merged review into proof tasks, and assemble the verdicts into verified.json.

  proof.py split --env RUN/env.sh
      Read RUN/merged.json. Write one RUN/proof/tasks/<mid>.json per behaviour claim
      (BUG, RISK, a MISSING raised by the tests agent) and per question, and list the
      rest in RUN/proof/static.json. Check out the base commit at RUN/base when there is
      anything to prove. Prints the mids to prove and the static count.

  proof.py assemble --env RUN/env.sh --n N
      Read RUN/merged.json, every RUN/proof/<mid>/result.json and RUN/static.json, and
      write RUN/verified.json. A claim with no result is kept as an open question.
"""
import argparse
import json
import pathlib
import shlex
import subprocess
import sys

PROVE_KINDS = {"BUG", "RISK"}
SEVERITIES = ["CRITICAL", "HIGH", "MEDIUM"]


def load_env(path):
    env = {}
    for line in pathlib.Path(path).read_text().splitlines():
        key, _, value = line.partition("=")
        if key:
            parts = shlex.split(value)
            env[key] = parts[0] if parts else ""
    return env


def needs_proof(entry):
    if entry["kind"] in PROVE_KINDS:
        return True
    return entry["kind"] == "MISSING" and "tests" in entry.get("raised_by", [])


def cmd_split(args):
    env = load_env(args.env)
    run = pathlib.Path(env["RUN"])
    merged = json.loads((run / "merged.json").read_text())
    tasks = run / "proof" / "tasks"
    tasks.mkdir(parents=True, exist_ok=True)
    prove, static = [], []
    for f in merged.get("findings", []):
        (prove if needs_proof(f) else static).append(f["mid"])
        if needs_proof(f):
            (tasks / f"{f['mid']}.json").write_text(json.dumps({"type": "finding", **f}, indent=1))
    for q in merged.get("questions", []):
        prove.append(q["mid"])
        (tasks / f"{q['mid']}.json").write_text(json.dumps({"type": "question", **q}, indent=1))
    (run / "proof" / "static.json").write_text(json.dumps({"mids": static}))
    base = run / "base"
    if prove and not base.exists():
        subprocess.run(["git", "-C", env["AGENT_ROOT"], "worktree", "add", "--detach", "--quiet",
                        str(base), env["BASE"]], check=True)
    print("prove:", " ".join(prove) or "none")
    print("static:", len(static))


def result_of(run, mid):
    p = run / "proof" / mid / "result.json"
    if not p.exists():
        return None
    try:
        return json.loads(p.read_text())
    except json.JSONDecodeError:
        return None


def proof_field(res):
    pr = res.get("proof") or {}
    lines = [f"{pr.get('method', '?')}: {pr.get('command', '')}".strip()]
    if pr.get("result"):
        lines.append(pr["result"])
    if pr.get("files"):
        lines.append("files: " + ", ".join(pr["files"]))
    return "\n".join(lines)


def cmd_assemble(args):
    env = load_env(args.env)
    run = pathlib.Path(env["RUN"])
    merged = json.loads((run / "merged.json").read_text())
    st_path = run / "static.json"
    st = json.loads(st_path.read_text()) if st_path.exists() else {}
    static = {s["mid"]: s for s in st.get("static", [])}
    carry = st.get("carry", {})
    out = {"findings": [], "questions": [], "refuted": [], "pre_existing": list(merged.get("pre_existing", [])),
           "nits": merged.get("nits", []), "checked_clear": merged.get("checked_clear", []),
           "prior": st.get("prior", [])}
    missing = []

    def refute(src, reason, res=None):
        out["refuted"].append({"title": src["title"], "file": (res or src).get("file", src.get("file")),
                               "line": (res or src).get("line", src.get("line")), "reason": reason,
                               "raised_by": src.get("raised_by", [])})

    def pre(src, reason):
        out["pre_existing"].append({"file": src.get("file"), "line": src.get("line"),
                                    "text": f"{src['title']}: {reason}"})

    def open_q(src, needs, text=None):
        out["questions"].append({"mid": src["mid"], "title": src["title"], "file": src.get("file"),
                                 "line": src.get("line"), "text": text or src.get("text", ""),
                                 "needs": needs, "raised_by": src.get("raised_by", [])})

    for f in merged.get("findings", []):
        f = dict(f)
        if needs_proof(f):
            res = result_of(run, f["mid"])
            if res is None:
                missing.append(f["mid"])
                open_q(f, "the prover returned no result", text=dict(f.get("fields", [])).get("Detail", ""))
                continue
            v = res.get("verdict")
            if v == "PROVEN":
                f.update(file=res.get("file", f["file"]), line=res.get("line", f["line"]), verdict="PROVEN",
                         verified=res.get("reason", ""))
                f["fields"] = list(f.get("fields", [])) + [["Proof", proof_field(res)]]
                out["findings"].append(f)
            elif v == "REFUTED":
                refute(f, res.get("reason", ""), res)
            elif v == "PRE_EXISTING":
                pre(f, res.get("reason", ""))
            else:
                open_q(f, res.get("reason", ""), text=dict(f.get("fields", [])).get("Detail", ""))
        else:
            s = static.get(f["mid"])
            if s is None:
                missing.append(f["mid"])
                f.update(verdict="UNCHECKED", verified="the static checker returned no verdict")
                out["findings"].append(f)
                continue
            if s["verdict"] == "REFUTED":
                refute(f, s.get("reason", ""), s)
            elif s["verdict"] == "PRE_EXISTING":
                pre(f, s.get("reason", ""))
            else:
                f.update(file=s.get("file", f["file"]), line=s.get("line", f["line"]), verdict="CONFIRMED",
                         verified=s.get("checked", ""))
                out["findings"].append(f)

    for q in merged.get("questions", []):
        res = result_of(run, q["mid"])
        if res is None:
            missing.append(q["mid"])
            open_q(q, "the prover returned no result")
            continue
        v = res.get("verdict")
        if v == "PROVEN":
            out["findings"].append({
                "mid": q["mid"], "kind": res.get("kind", "BUG"), "title": q["title"],
                "severity": res.get("severity", "MEDIUM"), "file": res.get("file", q["file"]),
                "line": res.get("line", q["line"]), "raised_by": q.get("raised_by", []),
                "verdict": "PROVEN", "verified": res.get("reason", ""), "from_question": True,
                "fields": [["Detail", q.get("text", "")], ["Proof", proof_field(res)]]})
        elif v == "REFUTED":
            refute(q, res.get("reason", ""), res)
        elif v == "PRE_EXISTING":
            pre(q, res.get("reason", ""))
        else:
            open_q(q, res.get("reason", ""))

    order = {s: i for i, s in enumerate(SEVERITIES)}
    out["findings"].sort(key=lambda f: order.get(f["severity"], len(order)))
    ids, k = {}, 0
    for f in out["findings"]:
        if f["mid"] in carry:
            ids[f["mid"]] = carry[f["mid"]]
        else:
            k += 1
            ids[f["mid"]] = f"r{args.n}-{k}"
        f["id"] = ids[f["mid"]]
    out["fix_together"] = [{"ids": [ids[m] for m in g.get("mids", []) if m in ids], "note": g.get("note", "")}
                           for g in merged.get("fix_together", [])]
    out["fix_together"] = [g for g in out["fix_together"] if len(g["ids"]) > 1]
    proven = sum(f["verdict"] == "PROVEN" for f in out["findings"])
    confirmed = len(out["findings"]) - proven
    out["verdict_note"] = (f"{proven} proven by running code, {confirmed} confirmed from the text, "
                           f"{len(out['refuted'])} refuted, {len(out['questions'])} could not be proven locally")
    (run / "verified.json").write_text(json.dumps(out, indent=1))
    print(run / "verified.json")
    print(out["verdict_note"])
    if missing:
        print("no result for:", " ".join(missing), file=sys.stderr)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("split")
    s.add_argument("--env", required=True)
    a = sub.add_parser("assemble")
    a.add_argument("--env", required=True)
    a.add_argument("--n", type=int, required=True)
    args = ap.parse_args()
    {"split": cmd_split, "assemble": cmd_assemble}[args.cmd](args)


if __name__ == "__main__":
    main()
