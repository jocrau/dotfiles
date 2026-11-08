import { View, div, svg } from "gpui-kit";
import { h_flex } from "gpui-base";
import { spaces, agents, theme, run, window, keys, readTextFile, home } from "herdr";

// Claude subscription usage, saved by the Claude Code status line
// (dotfiles/claude/statusline.py) on each response.
const USAGE = "/.local/state/claude-usage.json";
const WINDOWS = [["five_hour", "5h", 5 * 3600], ["seven_day", "7d", 7 * 86400]];
const BAR_W = 40;
const PACE_FROM = 0.1;          // too early in a window for a projection to mean much
const WARN = 90, OVER = 110;    // projected % used at reset
const STALE_AFTER = 30 * 60;    // no Claude response for this long: dim the numbers

const hhmm = (d) => `${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
function when(epoch, now) {
  const w = new Date(epoch * 1000);
  return w.toDateString() === new Date(now * 1000).toDateString() ? hhmm(w) : `${w.toLocaleDateString("en-US", { weekday: "short" })} ${hhmm(w)}`;
}
function ago(secs) {
  const m = Math.round(secs / 60);
  return m < 60 ? `${m}m ago` : m < 48 * 60 ? `${Math.round(m / 60)}h ago` : `${Math.round(m / 1440)}d ago`;
}

// Per window: share used, share of the window gone by, and the projected share
// at reset if usage keeps its pace. level: 0 fine, 1 close to the limit, 2 over.
function usage(data) {
  const now = Date.now() / 1000, limits = data?.rate_limits, seen = Number(data?.seen_at || 0);
  const rows = [];
  for (const [key, label, length] of WINDOWS) {
    const w = limits?.[key];
    if (!w) continue;
    const resets = Number(w.resets_at || 0);
    if (resets && resets < now) { rows.push({ label, expired: true, tip: `${label}: reset at ${when(resets, now)}, no Claude response since` }); continue; }
    const pct = Number(w.used_percentage || 0);
    const elapsed = resets ? Math.min(1, Math.max(0, 1 - (resets - now) / length)) : null;
    const proj = elapsed != null && elapsed >= PACE_FROM ? pct / elapsed : null;
    const level = pct >= 100 || (proj != null && proj > OVER) ? 2 : proj != null && proj >= WARN ? 1 : 0;
    const tip = [`${label}: ${pct.toFixed(0)}% used`]
      .concat(elapsed != null ? [`${Math.round(elapsed * 100)}% of window gone`] : [])
      .concat(proj != null ? [`on pace for ~${Math.round(proj)}%`] : elapsed != null ? ["too early to project"] : [])
      .concat(resets ? [`resets ${when(resets, now)}`] : [])
      .join(" · ");
    rows.push({ label, pct, elapsed, level, tip });
  }
  const stale = seen > 0 && now - seen > STALE_AFTER;
  const onCredits = rows.some((r) => r.pct >= 100);
  const tip = rows.map((r) => r.tip).concat(seen ? [`data from ${when(seen, now)} (${ago(now - seen)})${stale ? ", stale" : ""}`] : []).join("\n");
  return { rows, stale, onCredits, tip };
}

// Fill = share used; tick = share of the window gone by. Fill past the tick is over pace.
function paceBar(r, t, color) {
  const fill = Math.round(Math.min(100, r.pct) / 100 * BAR_W);
  return div().relative().w(BAR_W).h(5).rounded(2.5).bg(t.border)
    .child(div().absolute().left(0).top(0).h(5).w(fill).rounded(2.5).bg(color))
    .when(r.elapsed != null, (el) => el.child(div().absolute().top(-2).h(9).w(1.5).left(Math.max(0, Math.round(r.elapsed * BAR_W) - 1)).bg(t.foreground)));
}

function usageView(u, t) {
  const colors = [t.muted, t.ansi3, t.blocked];
  const row = h_flex().gap(10).items_center().text_color(t.muted).when(u.stale, (el) => el.opacity(0.5));
  for (const r of u.rows) {
    const color = colors[r.level ?? 0];
    row.child(h_flex().gap(5).items_center().text_color(color).child(r.label).when(!r.expired, (el) => el.child(paceBar(r, t, color)).child(`${r.pct.toFixed(0)}%`)).when(Boolean(r.expired), (el) => el.child("—")));
  }
  if (u.onCredits) row.child(div().text_color(t.blocked).child("on credits"));
  return div().id("usage").tooltip(u.tip).child(row);
}

export default class WorkspaceStatus extends View {
  init(_props, cx) {
    this.usage = null;
    cx.timer.every(15000, (cx) => this.load(cx));
    this.load(cx);
  }

  load(cx) {
    cx.spawn(async (cx) => {
      try { this.usage = JSON.parse(await readTextFile(home() + USAGE)); }
      catch { this.usage = null; }
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
      .when(Boolean(this.usage), el => {
        const u = usage(this.usage);
        return el.when(u.rows.length > 0, el => el.child(usageView(u, t)));
      })
      .child(div().id("palette").text_color(t.dim).on_click(() => run("app.palette")).child(this.hint(t)));
  }
}
