#!/usr/bin/env bash
# uninstall.sh - Uninstall Claude Recall
# Removes hook script, skill, and deregisters the PostToolUse hook.
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
  2. Removes ~/.claude/commands/analyze-patterns.md
  3. Removes the log-operations hook entry from ~/.claude/settings.json
     (preserves all other settings and hooks)
  4. Optionally removes ~/.claude/tool_logs/ (with --remove-logs or interactive prompt)
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
SETTINGS="$CLAUDE_DIR/settings.json"
LOGS_DIR="$CLAUDE_DIR/tool_logs"

echo ""
printf '%s=== Claude Recall - Uninstall ===%s\n' "$BOLD" "$RESET"
echo ""

# --- Confirm ---
if [ "$AUTO_YES" -eq 0 ]; then
    printf "This will remove Claude Recall hook and command. Continue? [y/N] "
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

# --- 1. Remove hook script ---
if [ -f "$HOOKS_DIR/log-operations.py" ]; then
    rm "$HOOKS_DIR/log-operations.py"
    ok "Removed hook: $HOOKS_DIR/log-operations.py"
else
    skip "Hook not found: $HOOKS_DIR/log-operations.py"
fi

# Clean up empty hooks directory
if [ -d "$HOOKS_DIR" ] && [ -z "$(ls -A "$HOOKS_DIR" 2>/dev/null)" ]; then
    rmdir "$HOOKS_DIR"
    ok "Removed empty directory: $HOOKS_DIR"
fi

# --- 2. Remove skill ---
if [ -f "$COMMANDS_DIR/analyze-patterns.md" ]; then
    rm "$COMMANDS_DIR/analyze-patterns.md"
    ok "Removed command: $COMMANDS_DIR/analyze-patterns.md"
else
    skip "Command not found: $COMMANDS_DIR/analyze-patterns.md"
fi

# Clean up empty commands directory
if [ -d "$COMMANDS_DIR" ] && [ -z "$(ls -A "$COMMANDS_DIR" 2>/dev/null)" ]; then
    rmdir "$COMMANDS_DIR"
    ok "Removed empty directory: $COMMANDS_DIR"
fi

# --- 3. Remove hook from settings.json ---
if [ -f "$SETTINGS" ]; then
    # Check Python 3 availability
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
        # Check if this entry contains our hook
        entry_str = json.dumps(entry)
        if hook_marker in entry_str:
            modified = True
            continue
        filtered.append(entry)
    if filtered:
        hooks[event_type] = filtered
    else:
        # Remove empty event type
        del hooks[event_type]

# Remove empty hooks section
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

# --- 4. Optionally remove log data ---
if [ -d "$LOGS_DIR" ]; then
    if [ "$REMOVE_LOGS" -eq 1 ]; then
        rm -rf "$LOGS_DIR"
        ok "Removed log directory: $LOGS_DIR"
    elif [ "$AUTO_YES" -eq 0 ]; then
        # Show log size for context
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
