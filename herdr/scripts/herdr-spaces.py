#!/usr/bin/python3 -I
"""The Spaces sidebar's `$action` line: shown only when a space needs you.

  ⚠ 2 waiting      agents in the space waiting for you (permission, input)
  #380 CI ✗        your PR for the space's branch needs you: feedback,
                   CI failing or conflicts, ready to merge (from pr-flow's
                   local queue; no network)
  ±3 uncommitted   uncommitted changes while no agent in the space works

Runs in the background, one per user: started by claude-summary.py (the
Claude hook) when it isn't running, it polls herdr every few seconds and
writes a workspace's token only when its line changes. Exits when the herdr
server is gone.
"""
import fcntl
import glob
import json
import os
import subprocess
import time

HERDR = "/opt/homebrew/bin/herdr"
STATE = os.path.expanduser("~/.local/state/herdr")
LOCK = os.path.join(STATE, "herdr-spaces.lock")
PR_FLOW_SETTINGS = os.path.expanduser("~/.claude/pr-flow/settings.json")
POLL = 3          # seconds between looks at herdr (agent states)
REPO_EVERY = 20   # seconds between git and pr-flow reads per space
PR_SHORT = {"CI failing": "CI ✗", "merge conflicts": "conflicts"}


def run(args, cwd=None):
    try:
        out = subprocess.run(args, capture_output=True, text=True, timeout=10, cwd=cwd)
        return out.stdout if out.returncode == 0 else None
    except Exception:
        return None


def snapshot():
    out = run([HERDR, "api", "snapshot"])
    try:
        return json.loads(out)["result"] if out else None
    except (ValueError, KeyError):
        return None


def find(obj, test):
    """Every dict inside `obj` that passes `test`."""
    if isinstance(obj, dict):
        if test(obj):
            yield obj
        for value in obj.values():
            yield from find(value, test)
    elif isinstance(obj, list):
        for value in obj:
            yield from find(value, test)


def my_prs():
    """Your open PRs that need you, by (repo name, branch): pr-flow's stages
    MY_FEEDBACK, MY_BLOCKED and MY_MERGE."""
    try:
        with open(PR_FLOW_SETTINGS, encoding="utf-8") as f:
            state_dir = os.path.expanduser(json.load(f)["state_dir"])
    except (OSError, ValueError, KeyError):
        return {}
    prs = {}
    for path in glob.glob(os.path.join(state_dir, "prs", "*.json")):
        try:
            with open(path, encoding="utf-8") as f:
                pr = json.load(f)
        except (OSError, ValueError):
            continue
        stage, snap = pr.get("stage"), pr.get("snapshot") or {}
        if pr.get("role") != "author" or stage not in ("MY_FEEDBACK", "MY_BLOCKED", "MY_MERGE"):
            continue
        repo, _, number = pr.get("key", "").partition("#")
        if stage == "MY_MERGE":
            why = "ready to merge"
        elif stage == "MY_FEEDBACK":
            why = "feedback"
        else:
            why = ", ".join(PR_SHORT.get(r, r) for r in pr.get("reasons") or []) or "blocked"
        prs[(repo.split("/")[-1], snap.get("headRef"))] = f"#{number} {why}"
    return prs


def repo_state(path):
    """(branch, uncommitted file count) of the checkout at `path`."""
    branch = (run(["git", "-C", path, "branch", "--show-current"]) or "").strip()
    status = run(["git", "-C", path, "status", "--porcelain"]) or ""
    return branch, len(status.splitlines())


def report(workspace, line):
    args = [HERDR, "workspace", "report-metadata", workspace, "--source", "herdr-spaces",
            "--seq", str(int(time.time() * 1000))]
    run(args + (["--token", f"action={line}"] if line else ["--clear-token", "action"]))


def main():
    os.makedirs(STATE, exist_ok=True)
    lock = open(LOCK, "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        return  # already running
    shown, repos, prs, read_at, misses = {}, {}, {}, 0, 0
    while True:
        snap = snapshot()
        if snap is None:
            misses += 1
            if misses >= 5:
                return  # the herdr server is gone
            time.sleep(POLL)
            continue
        misses = 0
        slow = time.monotonic() - read_at >= REPO_EVERY
        if slow:
            prs, read_at = my_prs(), time.monotonic()
        workspaces = list(find(snap, lambda o: "workspace_id" in o and "label" in o and "tab_count" in o))
        panes = list({p["pane_id"]: p for p in find(snap, lambda o: "pane_id" in o and "agent_status" in o)}.values())
        for ws in workspaces:
            wid = ws["workspace_id"]
            mine = [p for p in panes if p.get("workspace_id") == wid and p.get("agent")]
            parts = []
            waiting = sum(p.get("agent_status") == "blocked" for p in mine)
            if waiting:
                parts.append(f"⚠ {waiting} waiting")
            tree = ws.get("worktree") or {}
            path = tree.get("checkout_path")
            if path:
                if slow or path not in repos:
                    repos[path] = repo_state(path)
                branch, dirty = repos[path]
                pr = prs.get((tree.get("repo_name"), branch))
                if pr:
                    parts.append(pr)
                if dirty and not any(p.get("agent_status") == "working" for p in mine):
                    parts.append(f"±{dirty} uncommitted")
            line = " · ".join(parts)
            if shown.get(wid) != line:
                report(wid, line)
                shown[wid] = line
        time.sleep(POLL)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
