#!/usr/bin/env bash
# Install TokenBar agent-status hooks for Claude Code and Codex.
# Idempotent. Backs up existing configs. Uninstall: run with --uninstall
set -euo pipefail

HOOK_DIR="$HOME/.tokenbar"
HOOK_SCRIPT="$HOOK_DIR/hook.sh"
STATE_PREFIX="$HOOK_DIR/state"

mkdir -p "$HOOK_DIR"

cat > "$HOOK_SCRIPT" <<'HOOK'
#!/bin/bash
# Writes the most recent agent hook event to ~/.tokenbar/state-<provider>.json
# Python3-only on purpose: /usr/bin/python3 ships with the Command Line Tools
# that Claude Code itself requires, so no jq / ruby dependency.
# NOTE: use python3 -c, NOT a heredoc — a heredoc would replace stdin and the
# piped hook payload would never reach the script.
PROVIDER="${1:-unknown}"
TS="$(date +%s)"
OUT="$HOME/.tokenbar/state-${PROVIDER}.json"
if [ ! -t 0 ]; then
  /usr/bin/python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    d = {}
event = d.get("hook_event_name", "unknown")
cwd = d.get("cwd", "")
session = d.get("session_id", "")
# Which tool the agent is running (Bash/Read/Write/...) so the status line can
# show "干活中 · 项目 · 工具". Only present on Pre/PostToolUse events.
tool = d.get("tool_name", "") or ""
try:
    with open(sys.argv[1], "w") as f:
        json.dump({"event": event, "cwd": cwd, "session": session, "tool": tool, "ts": int(sys.argv[2])}, f)
except Exception:
    pass
' "$OUT" "$TS"
fi
HOOK
chmod +x "$HOOK_SCRIPT"

CLAUDE_SETTINGS="$HOME/.claude/settings.json"
CODEX_HOOKS="$HOME/.codex/hooks.json"

# Claude Code / Codex hook schema: each event maps to an array of *hook groups*,
# and each group must be { "hooks": [ { "type": "command", ... } ] } — a bare
# command object as the array element fails schema validation on load.
CLAUDE_GROUP="{\"hooks\":[{\"type\":\"command\",\"command\":\"$HOOK_SCRIPT claude\",\"timeout\":3}]}"
CODEX_GROUP="{\"hooks\":[{\"type\":\"command\",\"command\":\"$HOOK_SCRIPT codex\",\"timeout\":3}]}"

if [[ "${1:-}" == "--uninstall" ]]; then
  echo "Removing TokenBar hooks…"
  /usr/bin/python3 - "$CLAUDE_SETTINGS" "$CODEX_HOOKS" <<'PY'
import json, sys, os
for path in sys.argv[1:]:
    if not os.path.exists(path): continue
    bak = path + ".bak-tokenbar-" + str(int(__import__('time').time()))
    os.rename(path, bak)
    try:
        d = json.load(open(bak))
        for ev in list(d.get("hooks", {})):
            hooks = d["hooks"][ev]
            keep = [h for h in hooks if "tokenbar" not in json.dumps(h)]
            if keep: d["hooks"][ev] = keep
            else: del d["hooks"][ev]
        if d.get("hooks"): json.dump(d, open(path, "w"), indent=2)
        else: d.pop("hooks", None); json.dump(d, open(path, "w"), indent=2)
        print("cleaned:", path)
    except Exception as e:
        os.rename(bak, path)
        print("skip", path, e)
PY
  rm -f "$HOOK_DIR"/state-*.json
  echo "Done. Hooks removed (settings restored from backup on next reinstall)."
  exit 0
fi

# ---- Claude Code: merge into ~/.claude/settings.json ----
EVENTS=(UserPromptSubmit PreToolUse PostToolUse Notification Stop SessionEnd)
/usr/bin/python3 - "$CLAUDE_SETTINGS" "$CLAUDE_GROUP" "${EVENTS[@]}" <<'PY'
import json, os, sys
path, hook_json = sys.argv[1], sys.argv[2]
events = sys.argv[3:]
hook = json.loads(hook_json)
if os.path.exists(path):
    d = json.load(open(path))
else:
    d = {}
    os.makedirs(os.path.dirname(path), exist_ok=True)
d.setdefault("hooks", {})
changed = False
for ev in events:
    arr = d["hooks"].setdefault(ev, [])
    if not any("tokenbar" in json.dumps(h) for h in arr):
        arr.append(hook); changed = True
json.dump(d, open(path, "w"), indent=2)
print(("updated" if changed else "unchanged") + ":", path)
PY

# ---- Codex: merge into ~/.codex/hooks.json ----
# Codex is NOT Claude-shaped: its schema wraps everything under a top-level
# "hooks" object. A flat {"EventName": [...]} file parses as zero hooks and
# every event is silently ignored, so the state file never updates.
CODEX_EVENTS=(UserPromptSubmit PreToolUse PostToolUse PermissionRequest Stop)
/usr/bin/python3 - "$CODEX_HOOKS" "$CODEX_GROUP" "${CODEX_EVENTS[@]}" <<'PY'
import json, os, sys
path, hook_json = sys.argv[1], sys.argv[2]
events = sys.argv[3:]
hook = json.loads(hook_json)
if os.path.exists(path):
    d = json.load(open(path))
else:
    d = {}
    os.makedirs(os.path.dirname(path), exist_ok=True)
# Rehome any previously-written flat entries (they never ran, but drop them so
# the file stays valid and so --uninstall can find them in either shape).
for ev in list(d.keys()):
    if ev == "hooks":
        continue
    d.setdefault("hooks", {})[ev] = d.pop(ev)
d.setdefault("hooks", {})
changed = False
for ev in events:
    arr = d["hooks"].setdefault(ev, [])
    if not any("tokenbar" in json.dumps(h) for h in arr):
        arr.append(hook); changed = True
json.dump(d, open(path, "w"), indent=2)
print(("updated" if changed else "unchanged") + ":", path)
PY

echo ""
echo "✅ TokenBar agent-status hooks installed:"
echo "   state files: $STATE_PREFIX-<provider>.json  (claude / codex)"
echo "   claude settings: $CLAUDE_SETTINGS"
echo "   codex hooks:     $CODEX_HOOKS"
echo "   ⚠️ Restart running claude/codex sessions for hooks to take effect."
echo "   Uninstall: $0 --uninstall"
