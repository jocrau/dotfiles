#!/usr/bin/python3 -I
"""Give every Claude background session that isn't open in herdr its own workspace.

Bound to cmd+shift+a in ~/.config/herdr/config.toml. A session counts as open
when some pane's foreground process is `claude attach <id>` (same match as
claude-summary.py). New workspaces are named after the session, start in its
cwd, and don't take focus; a herdr notification reports what was attached.
"""
import json
import os
import subprocess

HERDR = "/opt/homebrew/bin/herdr"
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


def attached_ids(panes):
    """Session ids already attached in some herdr pane."""
    ids = set()
    for pane in panes:
        if pane.get("agent") != "claude":
            continue
        info = load_json([HERDR, "pane", "process-info", "--pane", pane["pane_id"]], {})
        for proc in info.get("result", {}).get("process_info", {}).get("foreground_processes", []):
            argv = proc.get("argv") or []
            if len(argv) >= 3 and argv[1] == "attach":
                ids.add(argv[2])
    return ids


def main():
    agents = load_json([CLAUDE, "agents", "--json", "--all"], [])
    panes = load_json([HERDR, "pane", "list"], {}).get("result", {}).get("panes", [])
    open_ids = attached_ids(panes)
    added = []
    for agent in agents:
        if agent.get("kind") != "background":
            continue
        keys = {agent.get("id"), agent.get("sessionId"), agent.get("name")}
        if keys & open_ids:
            continue
        name = agent.get("name") or agent.get("id")
        cwd = agent.get("cwd") if os.path.isdir(agent.get("cwd") or "") else os.path.expanduser("~")
        created = load_json([HERDR, "workspace", "create", "--cwd", cwd, "--label", name, "--no-focus"], {})
        pane = next((o["pane_id"] for o in _objects(created) if o.get("pane_id")), None)
        if not pane:
            continue
        run([HERDR, "pane", "run", pane, "claude attach " + agent["id"]])
        added.append(name)
    if added:
        body = ", ".join(added)
        run([HERDR, "notification", "show", f"Attached {len(added)} session(s)", "--body", body, "--sound", "none"])
    else:
        run([HERDR, "notification", "show", "All background sessions are already in herdr", "--sound", "none"])


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
