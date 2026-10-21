#!/usr/bin/python3 -I
"""Bring Claude background sessions into herdr and keep their panes in sync.

Bound to cmd+shift+a in ~/.config/herdr/config.toml. Two jobs:

- Attach: every background session that isn't open in herdr gets its own
  workspace, named after the session, started in its cwd, without focus.
- Re-sync: a session's viewer pane (`claude attach <id>`) keeps the folder it
  started in, so after `/cd` or a worktree switch herdr shows the wrong repo.
  Such panes are replaced by a fresh viewer started in the session's cwd, in
  the same tab; the session itself keeps running throughout.

A session counts as open when some pane's foreground process is
`claude attach <id>` (same match as claude-summary.py). A herdr notification
reports what was done.
"""
import json
import os
import subprocess
import time

HERDR = os.path.expanduser("~/.local/bin/herdr")  # herdr's own installer (herdr update), not Homebrew
CLAUDE = os.path.expanduser("~/.local/bin/claude")


def run(args):
    try:
        out = subprocess.run(args, capture_output=True, text=True, timeout=10)
        return out.stdout if out.returncode == 0 else ""
    except Exception:
        return ""


def load_json(args, default):
    try:
        return json.loads(run(args))
    except ValueError:
        return default


def viewers(panes):
    """Map each attached session id to (pane, viewer cwd)."""
    found = {}
    for pane in panes:
        if pane.get("agent") != "claude":
            continue
        info = load_json([HERDR, "pane", "process-info", "--pane", pane["pane_id"]], {})
        for proc in info.get("result", {}).get("process_info", {}).get("foreground_processes", []):
            argv = proc.get("argv") or []
            if len(argv) >= 3 and argv[1] == "attach":
                found[argv[2]] = (pane, proc.get("cwd") or pane.get("foreground_cwd") or "")
    return found


def wait_for(check, seconds):
    deadline = time.time() + seconds
    while time.time() < deadline:
        if check():
            return True
        time.sleep(0.2)
    return False


def resync(agent, pane):
    """Replace a viewer pane with one started in the session's cwd."""
    old = pane["pane_id"]
    split = [HERDR, "pane", "split", old, "--direction", "right", "--cwd", agent["cwd"]]
    split.append("--focus" if pane.get("focused") else "--no-focus")
    new = (load_json(split, {}).get("result", {}).get("pane", {}) or {}).get("pane_id")
    if not new:
        return False
    wait_for(lambda: run([HERDR, "pane", "read", new, "--source", "visible"]).strip(), 3)
    run([HERDR, "pane", "run", new, "claude attach " + agent["id"]])

    def attached():
        info = load_json([HERDR, "pane", "process-info", "--pane", new], {})
        procs = info.get("result", {}).get("process_info", {}).get("foreground_processes", [])
        return any((p.get("argv") or [])[1:3] == ["attach", agent["id"]] for p in procs)

    if not wait_for(attached, 8):
        run([HERDR, "pane", "close", new])  # keep the old viewer rather than lose it
        return False
    run([HERDR, "pane", "close", old])
    return True


def main():
    agents = load_json([CLAUDE, "agents", "--json", "--all"], [])
    panes = load_json([HERDR, "pane", "list"], {}).get("result", {}).get("panes", [])
    open_ = viewers(panes)
    added, synced = [], []
    for agent in agents:
        if agent.get("kind") != "background":
            continue
        name = agent.get("name") or agent.get("id")
        hit = next((open_[k] for k in (agent.get("id"), agent.get("sessionId"), agent.get("name")) if k in open_), None)
        if hit:
            pane, cwd = hit
            if os.path.isdir(agent.get("cwd") or "") and os.path.realpath(cwd) != os.path.realpath(agent["cwd"]):
                if resync(agent, pane):
                    synced.append(name)
            continue
        cwd = agent.get("cwd") if os.path.isdir(agent.get("cwd") or "") else os.path.expanduser("~")
        created = load_json([HERDR, "workspace", "create", "--cwd", cwd, "--label", name, "--no-focus"], {})
        new = next((o["pane_id"] for o in _objects(created) if o.get("pane_id")), None)
        if not new:
            continue
        run([HERDR, "pane", "run", new, "claude attach " + agent["id"]])
        added.append(name)
    parts = []
    if added:
        parts.append(f"attached {len(added)}: " + ", ".join(added))
    if synced:
        parts.append(f"moved {len(synced)} to their session's folder: " + ", ".join(synced))
    if parts:
        run([HERDR, "notification", "show", "Claude sessions", "--body", "; ".join(parts), "--sound", "none"])
    else:
        run([HERDR, "notification", "show", "All background sessions are in herdr and in sync", "--sound", "none"])
    print("; ".join(parts) or "nothing to do")


def _objects(value):
    """Every dict nested anywhere in a JSON value."""
    if isinstance(value, dict):
        yield value
        for v in value.values():
            yield from _objects(v)
    elif isinstance(value, list):
        for v in value:
            yield from _objects(v)


if __name__ == "__main__":
    main()
