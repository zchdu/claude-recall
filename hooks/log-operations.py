#!/usr/bin/env python3
"""Log Claude Code tool operations for pattern analysis.

PostToolUse hook - receives event JSON via stdin, appends a summary line to a
JSONL log file.  Large values (file contents, diffs) are truncated to keep
logs compact.  The log auto-rotates when it exceeds 10 MB (keeps the newer
half).

v2 additions (backward-compatible):
  - ver: format version (2)
  - tuid: tool_use_id (truncated to 20 chars)
  - res: tool_response summary (success/error/key fields, max 500 chars)

Safety: This script is invoked by Claude Code after every tool call.  Any
unhandled exception would surface as a hook error, so the entire main() body
is wrapped in a blanket try/except that silently swallows all failures --
logging must never interfere with normal Claude Code operation.

Concurrency: Multiple Claude Code sessions may run in parallel and append to
the same JSONL file.  We use fcntl.flock (advisory lock) on a separate lock
file to serialise writes and rotation, preventing interleaved lines or
partial truncation.
"""

import json
import os
import sys
import tempfile
from datetime import datetime, timezone

LOG_DIR = os.path.expanduser("~/.claude/tool_logs")
LOG_PATH = os.path.join(LOG_DIR, "operations.jsonl")
LOCK_PATH = os.path.join(LOG_DIR, ".operations.lock")
MAX_SIZE = 10 * 1024 * 1024  # 10 MB
MAX_STR_LEN = 300
MAX_RES_LEN = 500

# fcntl is only available on Unix; fall back to msvcrt on Windows.
_HAS_REAL_LOCK = False
try:
    import fcntl

    def _lock(f):
        fcntl.flock(f, fcntl.LOCK_EX)

    def _unlock(f):
        fcntl.flock(f, fcntl.LOCK_UN)

    _HAS_REAL_LOCK = True
except ImportError:
    try:
        import msvcrt

        def _lock(f):
            msvcrt.locking(f.fileno(), msvcrt.LK_LOCK, 1)

        def _unlock(f):
            msvcrt.locking(f.fileno(), msvcrt.LK_UNLCK, 1)

        _HAS_REAL_LOCK = True
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
    if isinstance(v, list):
        items = [truncate_value(item) for item in (v[:10] if len(v) > 20 else v)]
        if len(v) > 20:
            items.append(f"...({len(v)} items)")
        return items
    return v


def _summarize_response(tool_response):
    """Extract key fields from tool_response, truncate to MAX_RES_LEN.

    Keeps: success/error/exit_code/filePath/stderr (first line).
    Drops: large content/output blobs.
    """
    if not isinstance(tool_response, dict):
        if isinstance(tool_response, str):
            s = tool_response[:MAX_RES_LEN]
            return {"text": s} if s else {}
        return {}

    summary = {}

    # Boolean/numeric fields — always keep
    for key in ("success", "exit_code", "exitCode"):
        if key in tool_response:
            summary[key] = tool_response[key]

    # Short string fields — keep truncated
    for key in ("filePath", "file_path", "error", "message"):
        val = tool_response.get(key)
        if isinstance(val, str) and val:
            summary[key] = val[:200]

    # stderr first line
    stderr = tool_response.get("stderr", "")
    if isinstance(stderr, str) and stderr.strip():
        first_line = stderr.strip().split("\n")[0][:200]
        summary["stderr"] = first_line

    # stdout/output — just length hint
    for key in ("stdout", "output", "content"):
        val = tool_response.get(key)
        if isinstance(val, str) and len(val) > 100:
            summary[key + "_len"] = len(val)
        elif isinstance(val, str) and val:
            summary[key] = val

    # Ensure total JSON length stays within MAX_RES_LEN
    serialized = json.dumps(summary, ensure_ascii=False)
    if len(serialized) > MAX_RES_LEN:
        # Keep only the most important fields
        keep = {}
        for key in ("success", "exit_code", "exitCode", "error", "stderr"):
            if key in summary:
                keep[key] = summary[key]
        summary = keep

    return summary


MAX_SIZE_HARD = 50 * 1024 * 1024  # 50 MB hard cap for no-lock mode


def maybe_rotate():
    """If log exceeds MAX_SIZE, keep the newer half.

    Caller must already hold the lock file.
    Without real locking, only stops writing at a hard cap to prevent unbounded growth.
    """
    if not _HAS_REAL_LOCK:
        # Best-effort: stop appending if log exceeds hard cap
        try:
            if os.path.getsize(LOG_PATH) > MAX_SIZE_HARD:
                return "SKIP_WRITE"
        except OSError:
            pass
        return None
    try:
        if os.path.getsize(LOG_PATH) > MAX_SIZE:
            with open(LOG_PATH, "r", encoding="utf-8", errors="replace") as f:
                lines = f.readlines()
            kept = lines[len(lines) // 2 :]
            fd, tmp = tempfile.mkstemp(dir=LOG_DIR, suffix=".tmp")
            try:
                with os.fdopen(fd, "w", encoding="utf-8") as tf:
                    tf.writelines(kept)
                    tf.flush()
                    os.fsync(tf.fileno())
                os.replace(tmp, LOG_PATH)
            except Exception:
                try:
                    os.unlink(tmp)
                except OSError:
                    pass
                raise
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

    os.makedirs(LOG_DIR, mode=0o700, exist_ok=True)
    # Enforce permissions on existing directories/files
    try:
        os.chmod(LOG_DIR, 0o700)
    except OSError:
        pass
    if os.path.exists(LOG_PATH):
        try:
            os.chmod(LOG_PATH, 0o600)
        except OSError:
            pass

    tool_input = data.get("tool_input", {})
    if not isinstance(tool_input, dict):
        tool_input = {}

    summary = {k: truncate_value(v) for k, v in tool_input.items()}

    session_id = data.get("session_id", "")
    if not isinstance(session_id, str):
        session_id = str(session_id)

    # v2: extract tool_use_id
    tuid = data.get("tool_use_id", "")
    if not isinstance(tuid, str):
        tuid = str(tuid) if tuid else ""
    tuid = tuid[:20]

    # v2: summarize tool_response
    tool_response = data.get("tool_response", {})
    res = _summarize_response(tool_response)

    entry = {
        "ver": 2,
        "ts": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "sid": session_id[:16],
        "tool": data.get("tool_name", ""),
        "input": summary,
        "cwd": data.get("cwd", ""),
        "tuid": tuid,
        "res": res,
    }

    line = json.dumps(entry, ensure_ascii=False) + "\n"

    # Use an advisory file lock to serialise concurrent writers.
    # Open lock file with restricted permissions
    lock_fd_raw = os.open(LOCK_PATH, os.O_WRONLY | os.O_CREAT, 0o600)
    lock_fd = os.fdopen(lock_fd_raw, "w")
    try:
        _lock(lock_fd)
        if maybe_rotate() == "SKIP_WRITE":
            return
        # Open log file with restricted permissions on creation
        log_fd = os.open(LOG_PATH, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
        with os.fdopen(log_fd, "a", encoding="utf-8", errors="replace") as f:
            f.write(line)
    finally:
        _unlock(lock_fd)
        lock_fd.close()


if __name__ == "__main__":
    main()
