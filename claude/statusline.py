#!/usr/bin/python3 -I
"""Claude Code status line, one line:

  mm-plugin-marketplace ⎇ org-sync  main* ↑2↓5  Opus 5.5·high ⚡  ▰▰▰▱▱ 58% ↻180k/call  7d 100% on credits

repo (⎇ linked worktree), branch (* uncommitted, ↑ahead ↓behind), model
with effort (⚡ fast mode), context used as a bar (yellow from 60%, red
from 80%), and subscription usage only when a window is at 80% or more
(herdr's tab bar shows it always).

The burn hint `↻180k/call` shows, from 150k, how many tokens the last API
call read: every call (each tool step of a turn) re-reads the whole
context, so a large one uses the 5-hour and weekly limits fast, even when
the bar looks low on a 1M-token model. Time for /compact or a fresh session.

Also saves the rate limits for herdr's tab bar
(~/.config/herdr/scripts/claude-usage.py). Called by statusline-command.sh.
"""
import json
import os
import subprocess
import sys
import time

USAGE = os.path.expanduser("~/.local/state/claude-usage.json")
BURN_FROM, BURN_HIGH = 150_000, 400_000  # tokens read per call: hint, then red
BLUE, GREEN, YELLOW, RED, GRAY, RESET = "\033[34m", "\033[32m", "\033[33m", "\033[31m", "\033[90m", "\033[0m"


def save_usage(data):
    """The rate limits, for herdr's tab bar; written atomically."""
    try:
        os.makedirs(os.path.dirname(USAGE), exist_ok=True)
        tmp = f"{USAGE}.{os.getpid()}"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump({"seen_at": int(time.time()), "rate_limits": data.get("rate_limits")}, f)
        os.replace(tmp, USAGE)
    except OSError:
        pass


def git_state(cwd):
    """(branch, dirty, ahead, behind) from one quick git call;
    None outside a repo."""
    try:
        out = subprocess.run(["git", "-C", cwd, "--no-optional-locks", "status",
                              "--porcelain=v2", "--branch", "--untracked-files=normal"],
                             capture_output=True, text=True, timeout=1)
    except (OSError, subprocess.TimeoutExpired):
        return None
    if out.returncode != 0:
        return None
    branch, ahead, behind, dirty = "", 0, 0, False
    for line in out.stdout.splitlines():
        if line.startswith("# branch.head "):
            branch = line.split(" ", 2)[2]
        elif line.startswith("# branch.oid ") and not branch:
            branch = line.split(" ", 2)[2][:7]
        elif line.startswith("# branch.ab "):
            a, b = line.split()[2:4]
            ahead, behind = int(a), -int(b)
        elif not line.startswith("#"):
            dirty = True
    if branch == "(detached)":
        branch = ""
    return branch, dirty, ahead, behind


def bar(percent, steps=5):
    filled = min(steps, round(percent / 100 * steps))
    return "▰" * filled + "▱" * (steps - filled)


def main():
    try:
        data = json.load(sys.stdin)
    except ValueError:
        data = {}
    save_usage(data)
    workspace = data.get("workspace") or {}
    cwd = workspace.get("current_dir") or data.get("cwd") or os.getcwd()
    parts = []

    repo = (workspace.get("repo") or {}).get("name")
    git = git_state(cwd)
    if git and not repo:  # no origin remote: the checkout's top folder
        top = subprocess.run(["git", "-C", cwd, "rev-parse", "--show-toplevel"],
                             capture_output=True, text=True).stdout.strip()
        repo = os.path.basename(top) if top else ""
    where = f"{BLUE}{repo or os.path.basename(cwd)}{RESET}"
    if workspace.get("git_worktree"):
        where += f" {GRAY}⎇{RESET} {BLUE}{workspace['git_worktree']}{RESET}"
    parts.append(where)

    if git:
        branch, dirty, ahead, behind = git
        text = f"{GREEN}{branch}{RESET}" + (f"{YELLOW}*{RESET}" if dirty else "")
        sync = (f"↑{ahead}" if ahead else "") + (f"↓{behind}" if behind else "")
        parts.append(text + (f" {GRAY}{sync}{RESET}" if sync else ""))

    model = (data.get("model") or {}).get("display_name")
    if model:
        effort = (data.get("effort") or {}).get("level")
        text = f"{GRAY}{model}{'·' + effort if effort else ''}{RESET}"
        if data.get("fast_mode"):
            text += f" {YELLOW}⚡{RESET}"
        parts.append(text)

    context = data.get("context_window") or {}
    used = context.get("used_percentage")
    if used is not None:
        color = RED if used >= 80 else YELLOW if used >= 60 else GRAY
        text = f"{color}{bar(used)} {used:.0f}%{RESET}"
        read = context.get("total_input_tokens") or 0
        if read >= BURN_FROM:
            text += f" {RED if read >= BURN_HIGH else YELLOW}↻{read / 1000:.0f}k/call{RESET}"
        parts.append(text)

    limits, alerts, used_up, now = data.get("rate_limits") or {}, [], False, time.time()
    for key, label in (("five_hour", "5h"), ("seven_day", "7d")):
        window = limits.get(key) or {}
        percent = window.get("used_percentage")
        if percent is None or (window.get("resets_at") or now + 1) < now:
            continue
        if percent >= 80:
            alerts.append(f"{RED if percent >= 100 else YELLOW}{label} {percent:.0f}%{RESET}")
        used_up = used_up or percent >= 100
    if alerts:
        parts.append(" ".join(alerts) + (f" {RED}on credits{RESET}" if used_up else ""))

    print("  ".join(parts))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        print(os.path.basename(os.getcwd()))  # never leave the footer empty
