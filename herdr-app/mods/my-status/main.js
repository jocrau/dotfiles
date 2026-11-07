import { View, div, svg } from "gpui-kit";
import { h_flex } from "gpui-base";
import { spaces, agents, theme, run, window, keys, readTextFile, home } from "herdr";

// Claude subscription usage, as ~/.config/herdr/scripts/claude-usage.py printed it
// for the old herdr tab bar: saved by the Claude Code status line on each response.
const USAGE = "/.local/state/claude-usage.json";
const WINDOWS = [["five_hour", "5h"], ["seven_day", "7d"]];
const SHOW_RESET_FROM = 80;
const bar = (pct, steps = 5) => { const f = Math.min(steps, Math.round(pct / 100 * steps)); return "▰".repeat(f) + "▱".repeat(steps - f); };
function resetAt(epoch, now) {
  const w = new Date(epoch * 1000), n = new Date(now * 1000);
  const hm = `${String(w.getHours()).padStart(2, "0")}:${String(w.getMinutes()).padStart(2, "0")}`;
  return w.toDateString() === n.toDateString() ? hm : `${w.toLocaleDateString("en-US", { weekday: "short" })} ${hm}`;
}
function usageParts(limits) {
  const now = Date.now() / 1000, parts = [];
  let usedUp = false, worst = 0;
  for (const [key, label] of WINDOWS) {
    const w = limits?.[key];
    if (!w) continue;
    const resets = w.resets_at || 0;
    if (resets && resets < now) { parts.push(`${label} —`); continue; }
    const pct = Number(w.used_percentage || 0);
    usedUp ||= pct >= 100; worst = Math.max(worst, pct);
    parts.push(`${label} ${bar(pct)} ${pct.toFixed(0)}%` + (pct >= SHOW_RESET_FROM && resets ? ` ↻${resetAt(resets, now)}` : ""));
  }
  if (usedUp) parts.push("on credits");
  return { text: parts.join(" · "), worst };
}

export default class WorkspaceStatus extends View {
  init(_props, cx) {
    this.limits = null;
    cx.timer.every(15000, (cx) => this.load(cx));
    this.load(cx);
  }

  load(cx) {
    cx.spawn(async (cx) => {
      try { this.limits = JSON.parse(await readTextFile(home() + USAGE)).rate_limits ?? null; }
      catch { this.limits = null; }
      cx.notify();
    });
  }

  // The palette key as actually bound, not a hardcoded one; without a
  // binding the hint stays useful ("commands") instead of lying.
  hint(t) {
    const mac = window()?.platform === "macos";
    const mod = { cmd: mac ? "⌘" : "Ctrl+", ctrl: mac ? "⌃" : "Ctrl+", shift: mac ? "⇧" : "Shift+", alt: mac ? "⌥" : "Alt+", option: mac ? "⌥" : "Alt+" };
    const b = keys().find((k) => k.section === "global" && k.action === "app.palette");
    const parts = b && b.keys.endsWith("--") ? [...b.keys.slice(0, -2).split("-"), "-"] : b?.keys.split("-");
    const key = parts && parts.map((p) => mod[p.toLowerCase()] ?? p.toUpperCase()).join("");
    return key ? `${key}  commands` : "commands";
  }

  render() {
    const t = theme();
    const space = spaces().find(s => s.active);
    const list = agents();
    const needs = list.filter(a => a.status === "blocked").length;
    const label = (icon, text) => h_flex().gap(6).items_center().child(svg(`mods/workspace-chrome/${icon}.svg`).size(13)).child(text);
    return h_flex().size_full().px(14).gap(16).items_center().bg(t.chrome).border_t(1).border_color(t.border).text_size(11.8).text_color(t.muted)
      .child(label(space?.machine ? "server" : "monitor", space?.machine ?? "This computer"))
      .when(Boolean(space?.branch), el => el.child(label("branch", space.branch)))
      .child(h_flex().gap(6).items_center().child(div().size(6).rounded(3).bg(t.dim)).child(`${list.length} agents`)
        .when(needs > 0, el => el.child(div().text_color(t.blocked).child(`· ${needs} needs you`))))
      .child(div().flex_1())
      .when(Boolean(this.limits), el => {
        const u = usageParts(this.limits);
        return el.when(Boolean(u.text), el => el.child(div().text_color(u.worst >= 100 ? t.blocked : u.worst >= SHOW_RESET_FROM ? t.ansi3 : t.muted).child(u.text)));
      })
      .child(div().id("palette").text_color(t.dim).on_click(() => run("app.palette")).child(this.hint(t)));
  }
}
