#!/usr/bin/env bash
# install.sh - Install Claude Recall
# Copies hook script, skill, and registers the PostToolUse hook.
# Supports macOS and Linux. Requires Python 3.8+.
set -euo pipefail

# --- Color output ---
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    RESET='\033[0m'
else
    RED='' GREEN='' YELLOW='' CYAN='' BOLD='' RESET=''
fi

ok()   { printf "${GREEN}[OK]${RESET} %s\n" "$*"; }
skip() { printf "${YELLOW}[SKIP]${RESET} %s\n" "$*"; }
err()  { printf "${RED}[ERROR]${RESET} %s\n" "$*" >&2; }
info() { printf "${CYAN}[INFO]${RESET} %s\n" "$*"; }

# --- Help ---
usage() {
    cat <<EOF
${BOLD}Claude Recall - Installer${RESET}

Usage: $0 [OPTIONS]

Options:
  -h, --help    Show this help message and exit
  -f, --force   Overwrite existing files (hook, command) without prompting

What it does:
  1. Copies hooks/log-operations.py to ~/.claude/hooks/
  2. Copies commands/analyze-patterns.md to ~/.claude/commands/
  3. Registers the PostToolUse hook in ~/.claude/settings.json
     (safely merges with existing hooks if present)

Requirements:
  - Python 3.8+
  - Claude Code (https://docs.anthropic.com/en/docs/claude-code)
EOF
    exit 0
}

# --- Parse args ---
FORCE=0
for arg in "$@"; do
    case "$arg" in
        -h|--help)  usage ;;
        -f|--force) FORCE=1 ;;
        *)
            err "Unknown option: $arg"
            echo "Run '$0 --help' for usage."
            exit 1
            ;;
    esac
done

# --- Paths ---
CLAUDE_DIR="$HOME/.claude"
HOOKS_DIR="$CLAUDE_DIR/hooks"
COMMANDS_DIR="$CLAUDE_DIR/commands"
SETTINGS="$CLAUDE_DIR/settings.json"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo ""
printf '%s=== Claude Recall - Install ===%s\n' "$BOLD" "$RESET"
echo ""

# --- Pre-flight checks ---

# Check Python 3
if command -v python3 >/dev/null 2>&1; then
    PY_VER="$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
    PY_MAJOR="$(echo "$PY_VER" | cut -d. -f1)"
    PY_MINOR="$(echo "$PY_VER" | cut -d. -f2)"
    if [ "$PY_MAJOR" -lt 3 ] || { [ "$PY_MAJOR" -eq 3 ] && [ "$PY_MINOR" -lt 8 ]; }; then
        err "Python >= 3.8 required, found $PY_VER"
        exit 1
    fi
    ok "Python $PY_VER detected"
else
    err "Python 3 not found. Please install Python 3.8+ and retry."
    exit 1
fi

# Check Claude Code directory
if [ -d "$CLAUDE_DIR" ]; then
    ok "Claude Code directory found: $CLAUDE_DIR"
else
    info "Claude Code directory not found. Creating $CLAUDE_DIR"
    mkdir -p "$CLAUDE_DIR"
fi

# --- 1. Install hook ---
mkdir -p "$HOOKS_DIR"
SRC_HOOK="$SCRIPT_DIR/hooks/log-operations.py"
DST_HOOK="$HOOKS_DIR/log-operations.py"

if [ ! -f "$SRC_HOOK" ]; then
    err "Source hook not found: $SRC_HOOK"
    exit 1
fi

if [ -f "$DST_HOOK" ] && [ "$FORCE" -eq 0 ]; then
    # Check if content is identical
    if python3 -c "
import hashlib, sys
def h(p):
    with open(p,'rb') as f: return hashlib.sha256(f.read()).hexdigest()
sys.exit(0 if h('$SRC_HOOK') == h('$DST_HOOK') else 1)
" 2>/dev/null; then
        skip "Hook already installed (identical): $DST_HOOK"
    else
        info "Hook exists but differs. Updating: $DST_HOOK"
        cp "$SRC_HOOK" "$DST_HOOK"
        chmod +x "$DST_HOOK"
        ok "Hook updated: $DST_HOOK"
    fi
else
    cp "$SRC_HOOK" "$DST_HOOK"
    chmod +x "$DST_HOOK"
    ok "Hook installed: $DST_HOOK"
fi

# --- 2. Install skill ---
mkdir -p "$COMMANDS_DIR"
SRC_CMD="$SCRIPT_DIR/commands/analyze-patterns.md"
DST_CMD="$COMMANDS_DIR/analyze-patterns.md"

if [ ! -f "$SRC_CMD" ]; then
    err "Source command not found: $SRC_CMD"
    exit 1
fi

if [ -f "$DST_CMD" ] && [ "$FORCE" -eq 0 ]; then
    skip "Command already exists: $DST_CMD"
else
    cp "$SRC_CMD" "$DST_CMD"
    ok "Command installed: $DST_CMD"
fi

# --- 3. Register hook in settings.json ---
if [ ! -f "$SETTINGS" ]; then
    # No settings file: create fresh
    cat > "$SETTINGS" << 'JSON'
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "python3 $HOME/.claude/hooks/log-operations.py",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
JSON
    ok "Created $SETTINGS with hook config"
else
    # Settings file exists - use Python to safely merge
    MERGE_RESULT="$(python3 -c "
import json, sys

settings_path = '$SETTINGS'
hook_marker = 'log-operations'
hook_entry = {
    'matcher': '',
    'hooks': [
        {
            'type': 'command',
            'command': 'python3 \$HOME/.claude/hooks/log-operations.py',
            'timeout': 5
        }
    ]
}

try:
    with open(settings_path, 'r') as f:
        data = json.load(f)
except (json.JSONDecodeError, FileNotFoundError):
    print('CORRUPT')
    sys.exit(0)

# Check if hook is already registered
if hook_marker in json.dumps(data):
    print('EXISTS')
    sys.exit(0)

# Ensure hooks structure exists
if 'hooks' not in data:
    data['hooks'] = {}
if 'PostToolUse' not in data['hooks']:
    data['hooks']['PostToolUse'] = []

# Append our hook entry
data['hooks']['PostToolUse'].append(hook_entry)

with open(settings_path, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')

print('MERGED')
" 2>&1)" || true

    case "$MERGE_RESULT" in
        EXISTS)
            skip "Hook already registered in $SETTINGS"
            ;;
        MERGED)
            ok "Hook merged into existing $SETTINGS"
            ;;
        CORRUPT)
            err "Cannot parse $SETTINGS (invalid JSON)"
            err "Please manually add the hook config. See --help or README for details."
            ;;
        *)
            err "Failed to update $SETTINGS: $MERGE_RESULT"
            err "Please manually add the hook config. See --help or README for details."
            ;;
    esac
fi

# --- Done ---
echo ""
printf '%s=== Installation Complete ===%s\n' "$BOLD" "$RESET"
echo ""
info "Use Claude Code normally for a few sessions (3+ recommended)."
info "Then run the skill to analyze your patterns:"
echo ""
printf '    %s/analyze-patterns%s\n' "$BOLD" "$RESET"
echo ""
info "Logs are stored at: ~/.claude/tool_logs/operations.jsonl"
info "To uninstall, run: ./uninstall.sh"
