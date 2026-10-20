#!/usr/bin/python3 -I
"""Claude subscription usage for herdr's tab bar (ui.tab_bar_right command).

Prints e.g. `5h ▰▰▱▱▱ 42% · 7d ▰▰▰▰▱ 86% ↻Thu 08:00`: each window's share
used as a five-step bar, with its reset time from 80% on. Reads what the
Claude Code status line (~/.claude/statusline-command.sh) saved from its
input, so the numbers are as fresh as the last Claude response; a window
whose reset time has passed shows `—`. Prints nothing without data.

`· on credits` follows while a window is used up: further usage then draws
on extra-usage credits (if they're turned on for the account). The credit
amounts themselves aren't available to scripts: Claude Code shows them only
in /usage and at claude.ai/settings/usage.
"""
import json
import os
import time

USAGE = os.path.expanduser("~/.local/state/claude-usage.json")
WINDOWS = (("five_hour", "5h"), ("seven_day", "7d"))
SHOW_RESET_FROM = 80  # percent


def bar(percent, steps=5):
    filled = min(steps, round(percent / 100 * steps))
    return "▰" * filled + "▱" * (steps - filled)


def reset(epoch, now):
    """`14:30` today, else `Thu 08:00`."""
    when = time.localtime(epoch)
    same_day = time.strftime("%Y%m%d", when) == time.strftime("%Y%m%d", time.localtime(now))
    return time.strftime("%H:%M" if same_day else "%a %H:%M", when)


def main():
    try:
        with open(USAGE, encoding="utf-8") as f:
            limits = json.load(f).get("rate_limits") or {}
    except (OSError, ValueError):
        return
    now, parts, used_up = time.time(), [], False
    for key, label in WINDOWS:
        window = limits.get(key)
        if not window:
            continue
        resets = window.get("resets_at") or 0
        if resets and resets < now:  # a new window has started since
            parts.append(f"{label} —")
            continue
        percent = float(window.get("used_percentage") or 0)
        used_up = used_up or percent >= 100
        part = f"{label} {bar(percent)} {percent:.0f}%"
        if percent >= SHOW_RESET_FROM and resets:
            part += f" ↻{reset(resets, now)}"
        parts.append(part)
    if used_up:
        parts.append("on credits")
    if parts:
        print(" · ".join(parts))


if __name__ == "__main__":
    main()
