import { View, div } from "gpui-kit";
import { focused, hc, exec, home, openOverlay, closeOverlay, props, shared, setShared, notify } from "herdr";

// cmd+b (`mod.open:beads`): toggle beads-view for the focused terminal's repo
// as a dialog over the tab, like the old herdr TUI's full-tab beads view.
// This mod is only a launcher: it opens the terminal overlay and closes itself.
// Esc / q in beads-view ends the program, which closes the overlay too.
const VIEW = "/.config/herdr/scripts/beads-view";
const KEY = "beads.open"; // { overlay, terminal } while a beads view is open

// Nearest folder with a .beads directory, from cwd up (none: "").
const FIND_ROOT = 'd=$1; while [ "$d" != / ] && [ ! -d "$d/.beads" ]; do d=$(dirname "$d"); done; [ -d "$d/.beads" ] && printf %s "$d"';

async function isLive(address) {
  try {
    const r = await hc(["get", address, "--json"]);
    return r.code === 0 && JSON.parse(r.stdout).state === "live";
  } catch { return false; }
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
  const overlay = openOverlay({
    kind: "dialog", width: 0.92, height: 0.9,
    layout: { type: "block", content: { terminal } },
  });
  setShared(KEY, { overlay, terminal });
}

export default class Beads extends View {
  init(_props, cx) {
    cx.spawn(async (cx) => {
      try { await toggle(); }
      catch (e) { notify({ title: "Beads", body: String(e), level: "error" }); }
      closeOverlay(props().overlay);
    });
  }
  render() { return div(); }
}
