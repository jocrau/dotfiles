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

Failures stay visible rather than silent: a round that raises is logged to
~/.local/state/herdr/herdr-spaces.log and the next round runs; after a few
in a row, or when herdr's snapshot or pr-flow's records stop looking as
expected (an update changed them), it shows one herdr notification.
"""
import fcntl
import glob
import json
import os
import subprocess
import time
import traceback

HERDR = "/opt/homebrew/bin/herdr"
STATE = os.path.expanduser("~/.local/state/herdr")
LOCK = os.path.join(STATE, "herdr-spaces.lock")
LOG = os.path.join(STATE, "herdr-spaces.log")
PR_FLOW_SETTINGS = os.path.expanduser("~/.claude/pr-flow/settings.json")
POLL = 3          # seconds between looks at herdr (agent states)
REPO_EVERY = 20   # seconds between git and pr-flow reads per space
PR_SHORT = {"CI failing": "CI ✗", "merge conflicts": "conflicts"}
FAILURES_BEFORE_WARNING = 3
warned = set()


def log(text):
    """Append to the log, keeping its last 200 lines."""
    try:
        with open(LOG, encoding="utf-8") as f:
            lines = f.read().splitlines()[-199:]
    except OSError:
        lines = []
    lines.append(time.strftime("%Y-%m-%d %H:%M:%S ") + text.rstrip())
    with open(LOG, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


def warn(key, message):
    """Log, and show once per run as a herdr notification."""
    log(f"warning: {message}")
    if key not in warned:
        warned.add(key)
        run([HERDR, "notification", "show", "Spaces sidebar", "--body", message, "--sound", "none"])


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
    prs, records, readable = {}, 0, 0
    for path in glob.glob(os.path.join(state_dir, "prs", "*.json")):
        try:
            with open(path, encoding="utf-8") as f:
                pr = json.load(f)
        except (OSError, ValueError):
            continue
        records += 1
        readable += isinstance(pr, dict) and {"role", "stage", "key", "snapshot"} <= pr.keys()
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
    if records and not readable:
        warn("pr-flow", "pr-flow's PR records no longer have role/stage/key/snapshot: "
             "no PR lines. Update herdr-spaces.py for the new pr-flow.")
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


def tick(memo):
    """One round: look at herdr (and every REPO_EVERY s at git and pr-flow),
    write the lines that changed. False when herdr didn't answer."""
    snap = snapshot()
    if snap is None:
        return False
    slow = time.monotonic() - memo["read_at"] >= REPO_EVERY
    if slow:
        memo["prs"], memo["read_at"] = my_prs(), time.monotonic()
    workspaces = list(find(snap, lambda o: "workspace_id" in o and "label" in o and "tab_count" in o))
    panes = list({p["pane_id"]: p for p in find(snap, lambda o: "pane_id" in o and "agent_status" in o)}.values())
    if not workspaces or not panes:
        warn("herdr", "herdr's snapshot no longer has the workspaces and panes it expects: "
             "no Spaces lines. Update herdr-spaces.py for the new herdr.")
        return True
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
            if slow or path not in memo["repos"]:
                memo["repos"][path] = repo_state(path)
            branch, dirty = memo["repos"][path]
            pr = memo["prs"].get((tree.get("repo_name"), branch))
            if pr:
                parts.append(pr)
            if dirty and not any(p.get("agent_status") == "working" for p in mine):
                parts.append(f"±{dirty} uncommitted")
        line = " · ".join(parts)
        if memo["shown"].get(wid) != line:
            report(wid, line)
            memo["shown"][wid] = line
    return True


def main():
    os.makedirs(STATE, exist_ok=True)
    lock = open(LOCK, "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        return  # already running
    memo = {"shown": {}, "repos": {}, "prs": {}, "read_at": -REPO_EVERY}
    misses = failures = 0
    while True:
        try:
            answered = tick(memo)
            failures = 0
        except Exception:
            # One odd value mustn't stop the sidebar: log it, try again.
            answered, failures = True, failures + 1
            log(traceback.format_exc())
            if failures == FAILURES_BEFORE_WARNING:
                warn("crash", f"herdr-spaces.py failed {failures} times in a row; "
                     f"Spaces lines may be stale. See {LOG}.")
        misses = 0 if answered else misses + 1
        if misses >= 5:
            return  # the herdr server is gone
        time.sleep(POLL)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
