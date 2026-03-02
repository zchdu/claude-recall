#!/usr/bin/env python3
"""Log Claude Code tool operations for pattern analysis.

PostToolUse hook - receives event JSON via stdin, appends a summary line to a
JSONL log file.  Large values (file contents, diffs) are truncated to keep
logs compact.  The log auto-rotates when it exceeds 10 MB (keeps the newer
half).

Safety: This script is invoked by Claude Code after every tool call.  Any
unhandled exception would surface as a hook error, so the entire main() body
is wrapped in a blanket try/except that silently swallows all failures --
logging must never interfere with normal Claude Code operation.

Concurrency: Multiple Claude Code sessions may run in parallel and append to
the same JSONL file.  We use fcntl.flock (advisory lock) on a separate lock
file to serialise writes and rotation, preventing interleaved lines or
partial truncation.

Testing notes (unit-test sketch, not implemented here):
  - truncate_value: verify strings > MAX_STR_LEN are shortened; dicts and
    lists are recursed/capped; short values pass through unchanged.
  - maybe_rotate: create a file > MAX_SIZE, call maybe_rotate, assert the
    file shrank and starts with a complete JSON line.
  - main (integration): pipe a sample event JSON to stdin, assert a valid
    JSONL line was appended to the log file.
"""

import json
import os
import sys
from datetime import datetime, timezone

LOG_DIR = os.path.expanduser("~/.claude/tool_logs")
LOG_PATH = os.path.join(LOG_DIR, "operations.jsonl")
LOCK_PATH = os.path.join(LOG_DIR, ".operations.lock")
MAX_SIZE = 10 * 1024 * 1024  # 10 MB
MAX_STR_LEN = 300

# fcntl is only available on Unix; fall back to no-op on Windows.
try:
    import fcntl

    def _lock(f):
        fcntl.flock(f, fcntl.LOCK_EX)

    def _unlock(f):
        fcntl.flock(f, fcntl.LOCK_UN)
except ImportError:
    def _lock(f):
        pass

    def _unlock(f):
        pass


def truncate_value(v):
    """Truncate large string values, keep head + tail for context."""
    if isinstance(v, str) and len(v) > MAX_STR_LEN:
        return v[:200] + f" ...({len(v)} chars)... " + v[-50:]
    if isinstance(v, dict):
        return {k: truncate_value(val) for k, val in v.items()}
    if isinstance(v, list) and len(v) > 20:
        return v[:10] + [f"...({len(v)} items)"]
    return v


def maybe_rotate():
    """If log exceeds MAX_SIZE, keep the newer half.

    Caller must already hold the lock file.
    """
    try:
        if os.path.getsize(LOG_PATH) > MAX_SIZE:
            with open(LOG_PATH, "r") as f:
                lines = f.readlines()
            with open(LOG_PATH, "w") as f:
                f.writelines(lines[len(lines) // 2 :])
    except OSError:
        pass


def main():
    # --- Blanket guard: never raise to the caller ---
    try:
        _main_inner()
    except Exception:
        pass


def _main_inner():
    try:
        data = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return

    if not isinstance(data, dict):
        return

    os.makedirs(LOG_DIR, exist_ok=True)

    tool_input = data.get("tool_input", {})
    if not isinstance(tool_input, dict):
        tool_input = {}

    summary = {k: truncate_value(v) for k, v in tool_input.items()}

    session_id = data.get("session_id", "")
    if not isinstance(session_id, str):
        session_id = str(session_id)

    entry = {
        "ts": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "sid": session_id[:16],
        "tool": data.get("tool_name", ""),
        "input": summary,
        "cwd": data.get("cwd", ""),
    }

    line = json.dumps(entry, ensure_ascii=False) + "\n"

    # Use an advisory file lock to serialise concurrent writers.
    lock_fd = open(LOCK_PATH, "w")
    try:
        _lock(lock_fd)
        maybe_rotate()
        with open(LOG_PATH, "a") as f:
            f.write(line)
    finally:
        _unlock(lock_fd)
        lock_fd.close()


if __name__ == "__main__":
    main()
