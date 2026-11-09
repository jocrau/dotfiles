// A worktree's menu, opened by `worktree-support` as a popup with props
// { path, branch, machine, repoSpace, repoName, space, main, remove, pr, editors },
// or a top-level space's with { kind: "space", path, machine, space, editors, git, linked }.
// ↑/↓ move, Enter runs, Esc closes. Nothing here creates a worktree; removing
// one runs the repo's own `herdr.worktreeRemove` command, after asking.

import { View, div, svg } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { run, props, closeOverlay, openOverlay, setShared, exec, theme } from "herdr";

const quote = (s) => `'${String(s).replace(/'/g, `'\\''`)}'`;

// A folder on another machine opens over the editor's SSH remote, so it needs the CLI.
function editorItems(p) {
  return (p.editors ?? []).filter((e) => !p.machine || e.cli).map((e) => [`Open in ${e.label}`, "square-pen", () =>
    p.machine ? exec(e.cli, ["--remote", `ssh-remote+${p.machine}`, p.path])
      : e.cli ? exec(e.cli, [p.path]) : exec("open", ["-a", e.app, p.path])]);
}

function folderItems(p) {
  return [
    ["Copy path", "file-text", (cx) => cx.write_to_clipboard(p.path)],
    ...(p.machine ? [] : [["Reveal in Finder", "folder", () => exec("open", ["-R", p.path])]]),
  ];
}

function items(p) {
  // A top-level space row: where its terminal is now.
  if (p.kind === "space") return [
    ...editorItems(p),
    ...folderItems(p),
    // Herdr's own worktree dialog, sized as the shipped menu opens it.
    ...(p.git ? [
      ["New worktree", "git-branch", () => openOverlay({ mod: "worktree", kind: "dialog", width: 440, height: 260, props: { space: p.space, action: "new" } }), true],
      ["Open worktree", "git-branch", () => openOverlay({ mod: "worktree", kind: "dialog", width: 560, height: 480, props: { space: p.space, action: "open" } })],
    ] : []),
    ...(p.linked ? [herdrRemove(p.space)] : []),
    ["Rename", "square-pen", () => run("space.rename", { id: p.space }), !p.git],
    ["Close space", "x", () => run("space.close", { id: p.space })],
  ];
  const at = p.machine ? { machine: p.machine } : {};
  const list = [
    [p.space ? "Go to space" : "Open as space", "folder-plus", () =>
      p.space ? run("space.select", { id: p.space }) : run("space.new", { folder: p.path, ...at })],
    [`Open as tab in ${p.repoName}`, "terminal", () => run("tab.new", { space: p.repoSpace, folder: p.path })],
    // worktree-support does this one: it needs the new space's id.
    ["Show changes", "git-compare", () =>
      setShared("worktree-support.request", { id: `${Date.now()}-${Math.random()}`, at: Date.now(), action: "changes", path: p.path, machine: p.machine })],
    ...editorItems(p),
  ];
  if (p.pr) list.push(["Open pull request", "git-branch", (cx) => cx.open_url(p.pr)]);
  list.push(...folderItems(p));
  if (p.space) list.push(["Close space", "x", () => run("space.close", { id: p.space }), true]);
  if (p.remove) {
    const cmd = p.remove.replaceAll("{path}", quote(p.path)).replaceAll("{branch}", quote(p.branch ?? ""));
    list.push(["Remove worktree…", "archive", () => openOverlay({
      mod: "confirm", kind: "dialog", width: 420, height: 180,
      props: {
        title: `Remove ${p.branch ?? p.path}?`,
        detail: cmd,
        command: { name: "tab.new", args: { space: p.repoSpace, folder: p.main, name: `remove ${p.branch ?? ""}`.trim(), argv: ["sh", "-c", cmd] } },
      },
    }), !p.space]);
  } else if (p.space) list.push(herdrRemove(p.space));
  return list;
}

// Herdr's own removal of a worktree space, as the shipped menu offers it.
const herdrRemove = (space, apart) => ["Remove worktree", "archive",
  () => openOverlay({ mod: "worktree", kind: "dialog", width: 440, height: 260, props: { space, action: "remove" } }), apart];

export default class WorktreeActions extends View {
  init(_props, cx) {
    this.at = 0;
    this.handle = cx.focus_handle();
    this.handle.focus();
  }

  choose(i, cx) {
    const it = items(props() ?? {})[i];
    if (!it) return;
    closeOverlay(props()?.overlay);
    it[2](cx);
  }

  render() {
    const t = theme();
    const list = items(props() ?? {});
    return v_flex()
      .id("worktree-actions")
      .track_focus(this.handle)
      .w_full()
      .min_h(0)
      .p(5)
      .bg(t.popover)
      .text_size(12.8)
      .on_key_down((e, cx) => {
        if (e.key === "down") this.at = (this.at + 1) % list.length;
        else if (e.key === "up") this.at = (this.at + list.length - 1) % list.length;
        else if (e.key === "enter") return this.choose(this.at, cx);
        else if (e.key === "escape") return closeOverlay(props().overlay);
        else return;
        cx.notify();
      })
      .children(list.map((it, i) =>
        v_flex()
          // it[3]: the first of the destructive items, set apart.
          .when(Boolean(it[3]), (el) => el.child(div().mx(7).my(4).h(1).bg(t.border)))
          .child(h_flex()
            .id(`wa-${i}`)
            .h(31)
            .px(8)
            .gap(9)
            .rounded(7)
            .items_center()
            .text_color(t.foreground)
            .when(i === this.at, (el) => el.bg(t.selected))
            .hover((s) => s.bg(t.hover))
            .on_click((_e, cx) => this.choose(i, cx))
            .child(svg(`mods/workspace-chrome/${it[1]}.svg`).size(14).flex_none().text_color(t.muted))
            .child(div().flex_1().truncate().child(it[0]))),
      ));
  }
}
