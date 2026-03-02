#!/usr/bin/env bash
# uninstall.sh - Uninstall Claude Recall
# Removes hook, script, skills, and deregisters the PostToolUse hook.
# Optionally removes collected log data.
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
${BOLD}Claude Recall - Uninstaller${RESET}

Usage: $0 [OPTIONS]

Options:
  -h, --help        Show this help message and exit
  -y, --yes         Skip confirmation prompts (auto-yes)
  --remove-logs     Also remove collected log data (~/.claude/tool_logs/)

What it does:
  1. Removes ~/.claude/hooks/log-operations.py
  2. Removes ~/.claude/scripts/pre-analyze.py
  3. Removes ~/.claude/skills/analyze-patterns/
  4. Removes ~/.claude/commands/analyze-patterns.md
  5. Removes the log-operations hook entry from ~/.claude/settings.json
  6. Optionally removes ~/.claude/tool_logs/ (with --remove-logs or interactive prompt)
EOF
    exit 0
}

# --- Parse args ---
AUTO_YES=0
REMOVE_LOGS=0
for arg in "$@"; do
    case "$arg" in
        -h|--help)        usage ;;
        -y|--yes)         AUTO_YES=1 ;;
        --remove-logs)    REMOVE_LOGS=1 ;;
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
LOGS_DIR="$CLAUDE_DIR/tool_logs"

echo ""
printf '%s=== Claude Recall - Uninstall ===%s\n' "$BOLD" "$RESET"
echo ""

# --- Confirm ---
if [ "$AUTO_YES" -eq 0 ]; then
    printf "This will remove Claude Recall hook, script, and skills. Continue? [y/N] "
    read -r REPLY
    case "$REPLY" in
        [yY]|[yY][eE][sS]) ;;
        *)
            info "Uninstall cancelled."
            exit 0
            ;;
    esac
    echo ""
fi

# --- Helper ---
clean_empty_dir() {
    local path="$1"
    if [ -d "$path" ] && [ -z "$(ls -A "$path" 2>/dev/null)" ]; then
        rmdir "$path"
        ok "Removed empty directory: $path"
    fi
}

# --- 1. Remove hook ---
if [ -f "$HOOKS_DIR/log-operations.py" ]; then
    rm "$HOOKS_DIR/log-operations.py"
    ok "Removed hook: $HOOKS_DIR/log-operations.py"
else
    skip "Hook not found: $HOOKS_DIR/log-operations.py"
fi
clean_empty_dir "$HOOKS_DIR"

# --- 2. Remove pre-analyzer ---
if [ -f "$SCRIPTS_DIR/pre-analyze.py" ]; then
    rm "$SCRIPTS_DIR/pre-analyze.py"
    ok "Removed script: $SCRIPTS_DIR/pre-analyze.py"
else
    skip "Script not found: $SCRIPTS_DIR/pre-analyze.py"
fi
clean_empty_dir "$SCRIPTS_DIR"

# --- 3. Remove skill ---
if [ -d "$SKILLS_DIR/analyze-patterns" ]; then
    rm -rf "$SKILLS_DIR/analyze-patterns"
    ok "Removed skill: $SKILLS_DIR/analyze-patterns/"
else
    skip "Skill not found: $SKILLS_DIR/analyze-patterns/"
fi
clean_empty_dir "$SKILLS_DIR"

# --- 4. Remove legacy command ---
if [ -f "$COMMANDS_DIR/analyze-patterns.md" ]; then
    rm "$COMMANDS_DIR/analyze-patterns.md"
    ok "Removed command: $COMMANDS_DIR/analyze-patterns.md"
else
    skip "Command not found: $COMMANDS_DIR/analyze-patterns.md"
fi
clean_empty_dir "$COMMANDS_DIR"

# --- 5. Remove hook from settings.json ---
if [ -f "$SETTINGS" ]; then
    if ! command -v python3 >/dev/null 2>&1; then
        err "Python 3 not found. Cannot safely edit $SETTINGS"
        err "Please manually remove the 'log-operations' hook entry from $SETTINGS"
    else
        REMOVE_RESULT="$(python3 -c "
import json, sys

settings_path = '$SETTINGS'
hook_marker = 'log-operations'

try:
    with open(settings_path, 'r') as f:
        data = json.load(f)
except (json.JSONDecodeError, FileNotFoundError):
    print('CORRUPT')
    sys.exit(0)

if hook_marker not in json.dumps(data):
    print('NOT_FOUND')
    sys.exit(0)

modified = False
hooks = data.get('hooks', {})

for event_type in list(hooks.keys()):
    entries = hooks[event_type]
    if not isinstance(entries, list):
        continue
    filtered = []
    for entry in entries:
        entry_str = json.dumps(entry)
        if hook_marker in entry_str:
            modified = True
            continue
        filtered.append(entry)
    if filtered:
        hooks[event_type] = filtered
    else:
        del hooks[event_type]

if not hooks and 'hooks' in data:
    del data['hooks']

if not modified:
    print('NOT_FOUND')
    sys.exit(0)

with open(settings_path, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')

print('REMOVED')
" 2>&1)" || true

        case "$REMOVE_RESULT" in
            REMOVED)
                ok "Removed hook config from $SETTINGS"
                ;;
            NOT_FOUND)
                skip "Hook config not found in $SETTINGS"
                ;;
            CORRUPT)
                err "Cannot parse $SETTINGS (invalid JSON)"
                err "Please manually remove the 'log-operations' hook entry."
                ;;
            *)
                err "Failed to update $SETTINGS: $REMOVE_RESULT"
                err "Please manually remove the 'log-operations' hook entry."
                ;;
        esac
    fi
else
    skip "Settings file not found: $SETTINGS"
fi

# --- 6. Optionally remove log data ---
if [ -d "$LOGS_DIR" ]; then
    if [ "$REMOVE_LOGS" -eq 1 ]; then
        rm -rf "$LOGS_DIR"
        ok "Removed log directory: $LOGS_DIR"
    elif [ "$AUTO_YES" -eq 0 ]; then
        LOG_SIZE="unknown"
        if command -v du >/dev/null 2>&1; then
            LOG_SIZE="$(du -sh "$LOGS_DIR" 2>/dev/null | cut -f1)"
        fi
        echo ""
        printf "Remove collected log data? (%s in %s) [y/N] " "$LOG_SIZE" "$LOGS_DIR"
        read -r REPLY
        case "$REPLY" in
            [yY]|[yY][eE][sS])
                rm -rf "$LOGS_DIR"
                ok "Removed log directory: $LOGS_DIR"
                ;;
            *)
                info "Keeping log data at: $LOGS_DIR"
                ;;
        esac
    else
        info "Log data preserved at: $LOGS_DIR (use --remove-logs to delete)"
    fi
else
    skip "Log directory not found: $LOGS_DIR"
fi

# --- Done ---
echo ""
printf '%s=== Uninstall Complete ===%s\n' "$BOLD" "$RESET"
echo ""
info "Claude Recall has been removed."
info "Your other Claude Code settings are preserved."
