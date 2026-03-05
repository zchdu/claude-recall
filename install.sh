#!/usr/bin/env bash
# install.sh - Install Claude Recall
# Copies hook, pre-analyzer, skill, and registers the PostToolUse hook.
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
  -f, --force   Overwrite existing files without prompting

What it does:
  1. Copies hooks/log-operations.py to ~/.claude/hooks/
  2. Copies scripts/pre-analyze.py to ~/.claude/scripts/
  3. Copies skills/analyze-patterns/SKILL.md to ~/.claude/skills/analyze-patterns/
  4. Removes legacy command ~/.claude/commands/analyze-patterns.md (if present)
  5. Registers the PostToolUse hook in ~/.claude/settings.json

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
SKILLS_DIR="$CLAUDE_DIR/skills"
SCRIPTS_DIR="$CLAUDE_DIR/scripts"
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

# --- Helper: install a file ---
install_file() {
    local src="$1"
    local dst="$2"
    local label="$3"

    if [ ! -f "$src" ]; then
        err "Source not found: $src"
        return 1
    fi

    mkdir -p "$(dirname "$dst")"

    if [ -f "$dst" ] && [ "$FORCE" -eq 0 ]; then
        if python3 - "$src" "$dst" <<'PY' 2>/dev/null
import hashlib, sys
def h(p):
    with open(p, 'rb') as f: return hashlib.sha256(f.read()).hexdigest()
sys.exit(0 if h(sys.argv[1]) == h(sys.argv[2]) else 1)
PY
        then
            skip "$label already installed (identical): $dst"
            return 0
        else
            info "$label exists but differs. Updating: $dst"
        fi
    fi

    cp "$src" "$dst"
    chmod +x "$dst"
    ok "$label installed: $dst"
}

# --- 1. Install hook ---
install_file "$SCRIPT_DIR/hooks/log-operations.py" "$HOOKS_DIR/log-operations.py" "Hook"

# --- 2. Install pre-analyzer ---
install_file "$SCRIPT_DIR/scripts/pre-analyze.py" "$SCRIPTS_DIR/pre-analyze.py" "Pre-analyzer"

# --- 3. Install skill (new format) ---
install_file "$SCRIPT_DIR/skills/analyze-patterns/SKILL.md" "$SKILLS_DIR/analyze-patterns/SKILL.md" "Skill (analyze-patterns)"

# --- 4. Clean up legacy command (replaced by skills/ format) ---
DST_CMD="$COMMANDS_DIR/analyze-patterns.md"
if [ -f "$DST_CMD" ]; then
    rm "$DST_CMD"
    ok "Removed legacy command (replaced by skill): $DST_CMD"
fi

# --- 5. Register hook in settings.json ---
if [ ! -f "$SETTINGS" ]; then
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
    MERGE_RESULT="$(python3 - "$SETTINGS" <<'PY' 2>&1
import json, sys

settings_path = sys.argv[1]
hook_marker = 'log-operations'
hook_entry = {
    'matcher': '',
    'hooks': [
        {
            'type': 'command',
            'command': 'python3 $HOME/.claude/hooks/log-operations.py',
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

if hook_marker in json.dumps(data):
    print('EXISTS')
    sys.exit(0)

if 'hooks' not in data:
    data['hooks'] = {}
if 'PostToolUse' not in data['hooks']:
    data['hooks']['PostToolUse'] = []

data['hooks']['PostToolUse'].append(hook_entry)

with open(settings_path, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')

print('MERGED')
PY
)" || true

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
