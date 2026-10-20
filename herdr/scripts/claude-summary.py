#!/usr/bin/python3 -I
"""Claude Code hook: a one-line session summary in herdr's Agents sidebar.

Wired to Stop, UserPromptSubmit and Notification in ~/.claude/settings.json.
Writes the `summary` token of the session's herdr pane (`$summary` in the
[ui.sidebar.agents] rows of ~/.config/herdr/config.toml), and starts
herdr-spaces.py (the Spaces sidebar's `$action` line) when it isn't running.

Pane lookup follows the live process, not names or env vars (HERDR_* go
stale when a pane moves, and background sessions inherit them from wherever
they started): a background session is the pane running `claude attach <id>`,
an interactive one is the pane whose foreground process is the session's pid.
The last pane per session is cached. Never fails the hook.
"""
import json
import os
import re
import subprocess
import sys
import time

HERDR = "/opt/homebrew/bin/herdr"
SPACES = os.path.join(os.path.dirname(os.path.realpath(__file__)), "herdr-spaces.py")
SPACES_LOCK = os.path.expanduser("~/.local/state/herdr/herdr-spaces.lock")
CLAUDE = os.path.expanduser("~/.local/bin/claude")
MAX = 120
CACHE = os.path.expanduser("~/.local/state/herdr/claude-summary-panes.json")
MARKERS = (("needs input:", "? "), ("failed:", "✗ "), ("result:", "✓ "))


def run(args, cwd=None):
    try:
        out = subprocess.run(args, capture_output=True, text=True, timeout=5, cwd=cwd)
        return out.stdout if out.returncode == 0 else ""
    except Exception:
        return ""


def clip(text):
    text = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", text)  # [text](url) -> text
    text = " ".join(text.split())
    return text if len(text) <= MAX else text[: MAX - 1] + "…"


def last_assistant_text(path):
    """Text of the final assistant message in a transcript JSONL file."""
    try:
        with open(path, encoding="utf-8") as f:
            lines = f.readlines()[-400:]
    except OSError:
        return ""
    for line in reversed(lines):
        try:
            entry = json.loads(line)
        except ValueError:
            continue
        if entry.get("type") != "assistant":
            continue
        content = entry.get("message", {}).get("content", [])
        texts = [c.get("text", "") for c in content if isinstance(c, dict) and c.get("type") == "text"]
        if any(t.strip() for t in texts):
            return "\n".join(texts)
    return ""


def summarize_stop(event):
    text = event.get("last_assistant_message") or last_assistant_text(event.get("transcript_path", ""))
    lines = [l.strip() for l in text.splitlines() if l.strip()]
    for line in reversed(lines):
        low = line.lower()
        for marker, icon in MARKERS:
            if low.startswith(marker):
                return icon + line[len(marker):].strip()
    first = next((l for l in lines if not l.startswith(("```", "|", "#"))), "")
    return re.sub(r"[*`]", "", first)


def ensure_spaces():
    """Start herdr-spaces.py, detached, unless it holds its lock already."""
    import fcntl
    try:
        os.makedirs(os.path.dirname(SPACES_LOCK), exist_ok=True)
        with open(SPACES_LOCK, "a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)  # raises while it runs
            fcntl.flock(lock, fcntl.LOCK_UN)
    except OSError:
        return
    subprocess.Popen([SPACES], start_new_session=True, stdin=subprocess.DEVNULL,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def load_json(args):
    try:
        return json.loads(run(args))
    except ValueError:
        return None


def pane_matches(pane_id, entry):
    """Does this pane's foreground process belong to the session?"""
    info = load_json([HERDR, "pane", "process-info", "--pane", pane_id]) or {}
    procs = info.get("result", {}).get("process_info", {}).get("foreground_processes", [])
    for proc in procs:
        argv = proc.get("argv") or []
        if entry.get("kind") == "background":
            if len(argv) >= 3 and argv[1] == "attach" and argv[2] in (entry.get("id"), entry.get("sessionId"), entry.get("name")):
                return True
        elif entry.get("pid") and proc.get("pid") == entry.get("pid"):
            return True
    return False


def pane_for(session_id):
    """The session's (pane, workspace), or ("", "")."""
    agents = load_json([CLAUDE, "agents", "--json", "--all"]) or []
    # A resumed session (claude --continue) can be listed twice: a stale entry
    # without a process, and the live one. Try each, the live ones first.
    entries = sorted((a for a in agents if a.get("sessionId") == session_id),
                     key=lambda a: not a.get("pid"))
    if not entries:
        return "", ""

    def matches(pane_id):
        return any(pane_matches(pane_id, entry) for entry in entries)

    panes = (load_json([HERDR, "pane", "list"]) or {}).get("result", {}).get("panes", [])
    where = {p["pane_id"]: p["workspace_id"] for p in panes}
    try:
        with open(CACHE, encoding="utf-8") as f:
            cache = json.load(f)
    except (OSError, ValueError):
        cache = {}
    cached = cache.get(session_id)
    if cached in where and matches(cached):
        return cached, where[cached]
    for pane in panes:
        if pane.get("agent") == "claude" and pane["pane_id"] != cached and matches(pane["pane_id"]):
            cache[session_id] = pane["pane_id"]
            try:
                os.makedirs(os.path.dirname(CACHE), exist_ok=True)
                with open(CACHE, "w", encoding="utf-8") as f:
                    json.dump(cache, f)
            except OSError:
                pass
            return pane["pane_id"], pane["workspace_id"]
    return "", ""


def main():
    try:
        event = json.load(sys.stdin)
    except ValueError:
        return
    kind = event.get("hook_event_name", "")
    if kind == "Stop":
        summary = summarize_stop(event)
    elif kind == "UserPromptSubmit":
        prompt = (event.get("prompt") or "").strip().splitlines()
        summary = "… " + prompt[0] if prompt else ""
    elif kind == "Notification":
        message = event.get("message", "")
        if "waiting for your input" in message.lower():
            return  # Stop already reported something more specific
        summary = "⚠ " + message
    else:
        return
    pane, workspace = pane_for(event.get("session_id", ""))
    if not workspace:
        return
    token = ["--token", "summary=" + clip(summary)] if summary.strip() else ["--clear-token", "summary"]
    run([HERDR, "pane", "report-metadata", pane, "--source", "claude-summary",
         "--seq", str(int(time.time() * 1000)), *token])
    ensure_spaces()


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
