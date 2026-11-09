import { View, div } from "gpui-kit";
import { focused, terminals, hc, exec, home, openOverlay, closeOverlay, props, shared, setShared, notify } from "herdr";

// cmd+b (`mod.open:beads`): toggle beads-view for the focused terminal's repo
// as a dialog over the tab, with the keyboard on it.
// This mod is only a launcher: it starts beads-view, shows it and closes itself.
// Esc / q in beads-view ends the program, which closes the dialog too.
const VIEW = "/.local/bin/beads-view";
const KEY = "beads.open"; // { overlay, terminal } while a beads view is open

// Nearest folder with a .beads directory, from cwd up (none: "").
const FIND_ROOT = 'd=$1; while [ "$d" != / ] && [ ! -d "$d/.beads" ]; do d=$(dirname "$d"); done; [ -d "$d/.beads" ] && printf %s "$d"';

async function isLive(address) {
  try {
    const r = await hc(["get", address, "--json"]);
    return r.code === 0 && JSON.parse(r.stdout).state === "live";
  } catch { return false; }
}

// Show it in a dialog over the tab. The app only sees a terminal started
// with `hc run` a moment later, so wait for it first. Closing this launcher
// popup hands the keyboard back to what was under it, so close it first and
// open the dialog in the same tick, which leaves the keyboard on beads-view
// (closing ends this copy's tasks at their next await, not before).
async function showWhenSeen(cx, terminal) {
  for (let i = 0; i < 40; i++) {
    if (terminals().some((t) => t.address === terminal)) {
      closeOverlay(props().overlay);
      const overlay = openOverlay({
        kind: "dialog", width: 0.92, height: 0.9,
        layout: { type: "block", content: { terminal } },
      });
      setShared(KEY, { overlay, terminal });
      return;
    }
    await cx.sleep(50);
  }
  notify({ title: "Beads", body: `beads-view (${terminal}) didn't show up.`, level: "error" });
}

async function toggle() {
  const open = shared(KEY);
  if (open && await isLive(open.terminal)) {
    closeOverlay(open.overlay);
    await hc(["kill", open.terminal]);
    setShared(KEY, null);
    return;
  }
  setShared(KEY, null);

  const cwd = focused()?.cwd || home();
  const root = (await exec("/bin/sh", ["-c", FIND_ROOT, "sh", cwd])).stdout.trim();
  if (!root) {
    notify({ title: "No beads here", body: `No .beads folder in ${cwd} or above.`, level: "info", timeout: 4000 });
    return;
  }
  const r = await hc(["run", "--bg", "--json", "--cwd", root, "--label", "beads.view=1", "--", home() + VIEW]);
  if (r.code !== 0) {
    notify({ title: "beads-view didn't start", body: r.stderr.trim(), level: "error" });
    return;
  }
  const terminal = JSON.parse(r.stdout).address;
  setShared(KEY, { terminal });
  return terminal;
}

export default class Beads extends View {
  init(_props, cx) {
    cx.spawn(async (cx) => {
      let terminal;
      try { terminal = await toggle(); }
      catch (e) { notify({ title: "Beads", body: String(e), level: "error" }); }
      if (terminal) await showWhenSeen(cx, terminal);
      closeOverlay(props().overlay); // no-op if showWhenSeen closed it
    });
  }
  render() { return div(); }
}
