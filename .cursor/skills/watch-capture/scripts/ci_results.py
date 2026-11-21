#!/usr/bin/env python3
"""Watch capture kit: read a "Watch build" CI run through `gh api` job logs.

  ci_results.py --repo OWNER/NAME --branch BRANCH [--out DIR] [--run RUN_ID]

Prints each job's result. For a failed job it prints the compiler crash context and failure lines
the workflow writes into its log, and it saves the Watch screenshots (printed into the log as
base64) as PNG files in DIR. Job logs are used because artifact downloads can be unreachable from
where an agent reads results. Standard library only, plus the `gh` command.
"""
import argparse
import base64
import json
import re
import subprocess
import sys
from pathlib import Path


def gh(path):
    out = subprocess.run(["gh", "api", path], capture_output=True, text=True)
    if out.returncode != 0:
        sys.exit(f"gh api {path} failed: {out.stderr.strip()}")
    return out.stdout


def latest_run(repo, branch):
    runs = json.loads(gh(f"repos/{repo}/actions/runs?branch={branch}&per_page=20"))["workflow_runs"]
    runs = [r for r in runs if r["name"] == "Watch build"]
    if not runs:
        sys.exit(f"No 'Watch build' run on {branch}")
    return runs[0]


def section(lines, title, stop_prefixes=("-----", "##[")):
    start = None
    for i, line in enumerate(lines):
        if line.strip() == f"----- {title} -----":
            start = i  # the last match is the output; earlier ones are the echoed script
    if start is None:
        return []
    out = []
    for line in lines[start + 1:]:
        if line.startswith(stop_prefixes):
            break
        out.append(line)
    return out


def screenshots(lines, out_dir):
    out_dir.mkdir(parents=True, exist_ok=True)
    name, buf, saved = None, [], []
    for line in lines:
        m = re.fullmatch(r"WATCH-SCREENSHOT-(BEGIN|END) (\S+\.png)", line)
        if m and m.group(1) == "BEGIN":
            name, buf = m.group(2), []
        elif m and name == m.group(2):
            path = out_dir / name
            path.write_bytes(base64.b64decode("".join(buf)))
            saved.append(path)
            name = None
        elif name and re.fullmatch(r"[A-Za-z0-9+/=]+", line):
            buf.append(line)
    return saved


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--repo", required=True)
    parser.add_argument("--branch", required=True)
    parser.add_argument("--run", help="a specific run id instead of the branch's latest")
    parser.add_argument("--out", default="watch-ci-results")
    args = parser.parse_args()
    run = json.loads(gh(f"repos/{args.repo}/actions/runs/{args.run}")) if args.run else latest_run(args.repo, args.branch)
    print(f"run {run['id']} on {run['head_sha'][:7]}: {run['status']} {run.get('conclusion') or ''}")
    jobs = json.loads(gh(f"repos/{args.repo}/actions/runs/{run['id']}/jobs"))["jobs"]
    for job in jobs:
        failed = [s["name"] for s in job["steps"] if s.get("conclusion") == "failure"]
        print(f"- {job['name']}: {job['status']} {job.get('conclusion') or ''}" + (f" (failed: {', '.join(failed)})" if failed else ""))
        if job["status"] != "completed":
            continue
        lines = [re.sub(r"^\S+Z ", "", l).rstrip() for l in gh(f"repos/{args.repo}/actions/jobs/{job['id']}/logs").splitlines()]
        version = next((l for l in lines if re.match(r"Xcode \d", l)), None)
        if version:
            print(f"  {version}")
        if job.get("conclusion") == "failure":
            for title in ("compiler crash context", "failure lines", "last 60 lines"):
                body = [l for l in section(lines, title) if l.strip()]
                if title == "compiler crash context":
                    # The useful lines name the compiler, the file and the function it was emitting.
                    body = [l for l in body if re.search(r"Swift version|While |Command \w+ failed", l)] or body
                if body:
                    print(f"  --- {title} ---")
                    for l in body[-40:]:
                        print("  " + l[:300])
        for path in screenshots(lines, Path(args.out)):
            print(f"  screenshot: {path}")


if __name__ == "__main__":
    main()
