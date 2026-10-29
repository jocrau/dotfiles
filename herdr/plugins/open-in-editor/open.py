"""herdr link handler: open a clicked file:// link in VS Code (`code -g`).

The URL comes in HERDR_PLUGIN_CLICKED_URL. A line can follow the path as
`:12` or `:12:5`, or as a `#L12` / `#12` fragment. EDITOR_CLI overrides the
editor command (anything that takes `-g path:line`, e.g. cursor).
"""
import os
import re
import shutil
import subprocess
import sys
from urllib.parse import unquote, urlsplit

url = os.environ.get("HERDR_PLUGIN_CLICKED_URL", "") or (sys.argv[1] if len(sys.argv) > 1 else "")
parts = urlsplit(url)
path, line = unquote(parts.path), ""
m = re.match(r"L?(\d+)(?:[:C-]?(\d+))?$", parts.fragment)
if m:
    line = ":" + m.group(1) + (":" + m.group(2) if m.group(2) else "")
else:
    m = re.search(r"(:\d+(?::\d+)?)$", path)
    if m and not os.path.exists(path):
        path, line = path[: m.start()], m.group(1)

editor = os.environ.get("EDITOR_CLI") or shutil.which("code") or "/usr/local/bin/code"
print(f"{url} -> {editor} -g {path + line}")  # shows in herdr plugin log list
subprocess.Popen([editor, "-g", path + line], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                 start_new_session=True)
