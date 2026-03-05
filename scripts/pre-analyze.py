#!/usr/bin/env python3
"""Pre-analyze Claude Code tool logs for pattern detection.

Crunches raw JSONL into a structured summary so Claude reads ~10KB instead of
thousands of log lines.  Saves ~80% tokens compared to raw JSONL analysis.

Usage:
  python3 pre-analyze.py [--days N]

Constraints: stdlib only, Python 3.8+, streaming read.
"""

import json
import os
import sys
from collections import Counter, defaultdict
from datetime import datetime, timezone, timedelta
from pathlib import Path

LOG_DIR = Path.home() / ".claude" / "tool_logs"
OPS_LOG = LOG_DIR / "operations.jsonl"
COMMANDS_DIR = Path.home() / ".claude" / "commands"
SKILLS_DIR = Path.home() / ".claude" / "skills"


def _strip_wrapping_quotes(value):
    if len(value) >= 2 and (
        (value[0] == '"' and value[-1] == '"')
        or (value[0] == "'" and value[-1] == "'")
    ):
        return value[1:-1].strip()
    return value


def _first_content_line(content, skip_prefixes):
    for line in content.split("\n"):
        stripped = line.strip()
        if not stripped:
            continue
        if any(stripped.startswith(prefix) for prefix in skip_prefixes):
            continue
        return stripped[:100]
    return ""


def _extract_skill_description(content):
    body = content
    lines = content.splitlines()

    # Parse optional YAML frontmatter and prefer `description:` there.
    if lines and lines[0].strip() == "---":
        end_idx = None
        for i in range(1, len(lines)):
            if lines[i].strip() == "---":
                end_idx = i
                break

        if end_idx is not None:
            frontmatter_lines = lines[1:end_idx]
            for line in frontmatter_lines:
                stripped = line.strip()
                if stripped.lower().startswith("description:"):
                    desc = stripped.split(":", 1)[1].strip()
                    desc = _strip_wrapping_quotes(desc)
                    if desc:
                        return desc[:100]
            body = "\n".join(lines[end_idx + 1:])

    return _first_content_line(body, skip_prefixes=("#", "!"))


def parse_ts(ts_str):
    try:
        ts_str = ts_str.rstrip("Z") + "+00:00" if ts_str.endswith("Z") else ts_str
        dt = datetime.fromisoformat(ts_str)
        # Normalize naive timestamps to UTC to avoid comparison errors
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt
    except (ValueError, AttributeError):
        return None


def cutoff_ts(days):
    return datetime.now(timezone.utc) - timedelta(days=days)


def stream_jsonl(path, min_ts=None):
    # Normalize min_ts to timezone-aware UTC
    if min_ts is not None and hasattr(min_ts, 'tzinfo') and min_ts.tzinfo is None:
        min_ts = min_ts.replace(tzinfo=timezone.utc)
    try:
        f = open(path, "r", encoding="utf-8", errors="replace")
    except OSError:
        return
    with f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue
            if not isinstance(obj, dict):
                continue
            if min_ts:
                ts = parse_ts(obj.get("ts", ""))
                if not ts or ts < min_ts:
                    continue
            yield obj


def extract_bash_cmd(tool_input):
    cmd = tool_input.get("command", "")
    return cmd[:120] if isinstance(cmd, str) else ""


def extract_bash_base(tool_input):
    cmd = tool_input.get("command", "")
    if not isinstance(cmd, str):
        return ""
    parts = cmd.strip().split()
    return parts[0] if parts else ""


def scan_skills():
    skills = {}
    for d, suffix, stype in [
        (COMMANDS_DIR, ".md", "command"),
        (SKILLS_DIR, None, "skill"),
    ]:
        if not d.exists():
            continue
        try:
            entries = list(d.iterdir())
        except OSError:
            continue
        if stype == "command":
            for f in entries:
                if f.suffix == ".md" and f.is_file():
                    try:
                        content = f.read_text(encoding="utf-8", errors="replace")[:500]
                        desc = _first_content_line(content, skip_prefixes=("#",))
                    except OSError:
                        desc = ""
                    skills[f.stem] = desc
        else:
            for sd in entries:
                if sd.is_dir() and (sd / "SKILL.md").exists():
                    try:
                        content = (sd / "SKILL.md").read_text(encoding="utf-8", errors="replace")[:500]
                        desc = _extract_skill_description(content)
                    except OSError:
                        desc = ""
                    skills[sd.name] = desc
    return skills


def main():
    import argparse

    parser = argparse.ArgumentParser(description="Pre-analyze Claude Code tool logs")
    parser.add_argument("--days", type=int, default=30, help="Days to analyze (default: 30)")
    args = parser.parse_args()

    min_ts = cutoff_ts(args.days)
    out = []

    # --- Collect statistics ---
    total = 0
    sessions = set()
    tool_counter = Counter()
    bash_cmds = Counter()
    cwd_counter = Counter()
    ts_first = ts_last = None

    session_tools = defaultdict(list)
    session_bash = defaultdict(list)

    for entry in stream_jsonl(OPS_LOG, min_ts):
        total += 1
        sid = entry.get("sid", "")
        tool = entry.get("tool", "")
        inp = entry.get("input", {})
        cwd = entry.get("cwd", "")

        sessions.add(sid)
        tool_counter[tool] += 1
        if cwd:
            cwd_counter[cwd] += 1

        ts = parse_ts(entry.get("ts", ""))
        if ts:
            if ts_first is None or ts < ts_first:
                ts_first = ts
            if ts_last is None or ts > ts_last:
                ts_last = ts

        if not isinstance(inp, dict):
            inp = {}

        # Build per-session sequences
        key = ""
        if tool == "Bash":
            cmd = extract_bash_cmd(inp)
            if cmd:
                bash_cmds[cmd] += 1
                key = cmd[:80]
        elif tool in ("Edit", "Write", "Read"):
            key = str(inp.get("file_path", ""))[:60]
        elif tool == "Glob":
            key = str(inp.get("pattern", ""))[:60]
        elif tool == "Grep":
            key = str(inp.get("pattern", ""))[:60]

        session_tools[sid].append((tool, key))
        if tool == "Bash" and key:
            session_bash[sid].append(key)

    if total == 0:
        print("No log entries found. Use Claude Code for a few sessions, then try again.")
        print(f"Log: {OPS_LOG}")
        return

    n_sessions = len(sessions)
    span = ""
    if ts_first and ts_last:
        d = (ts_last - ts_first).days
        span = f"{d}d" if d > 0 else "<1d"

    out.append("## Statistics\n")
    out.append(f"- Records: {total} | Sessions: {n_sessions} | Span: {span} | Filter: last {args.days} days\n")

    out.append("### Tool Frequency (Top 5)\n")
    for t, c in tool_counter.most_common(5):
        out.append(f"- {t}: {c} ({c*100//total}%)")
    out.append("")

    out.append("### Top Bash Commands\n")
    for cmd, c in bash_cmds.most_common(10):
        out.append(f"- `{cmd}` ({c}x)")
    out.append("")

    out.append("### Top Directories\n")
    for cwd, c in cwd_counter.most_common(5):
        out.append(f"- `{cwd}` ({c}x)")
    out.append("")

    # --- Pattern detection ---
    min_sess = 2 if n_sessions < 3 else 3

    # Repeated Bash commands across sessions
    cmd_sids = defaultdict(set)
    for sid, cmds in session_bash.items():
        for cmd in set(cmds):
            cmd_sids[cmd].add(sid)

    repeated_cmds = {c: s for c, s in cmd_sids.items() if len(s) >= min_sess}

    # Command sequences (2-3 step N-grams)
    ngram_sids = defaultdict(set)
    for sid, tools in session_tools.items():
        seq = [(t, k) for t, k in tools if k]
        for n in (2, 3):
            for i in range(len(seq) - n + 1):
                gram = tuple(seq[i:i + n])
                # Must contain at least one Bash; pure Edit/Read sequences are too generic
                if any(t == "Bash" for t, _ in gram):
                    ngram_sids[gram].add(sid)

    repeated_ngrams = {g: s for g, s in ngram_sids.items() if len(s) >= min_sess}

    # Workflow patterns
    workflow_sids = defaultdict(set)
    for sid, cmds in session_bash.items():
        bases = set(extract_bash_base({"command": c}) for c in cmds)
        joined = " ".join(cmds)
        if {"rsync", "ssh"} <= bases or {"scp", "ssh"} <= bases:
            workflow_sids["deploy (rsync/scp + ssh)"].add(sid)
        if "docker" in bases:
            workflow_sids["docker workflow"].add(sid)
        if "cargo" in bases:
            workflow_sids["rust build/test"].add(sid)
        if "pytest" in bases or ("npm" in bases and "test" in joined):
            workflow_sids["test workflow"].add(sid)

    repeated_wf = {n: s for n, s in workflow_sids.items() if len(s) >= min_sess}

    # --- Existing skills ---
    skills = scan_skills()
    out.append("## Existing Skills\n")
    if skills:
        for name, desc in sorted(skills.items()):
            out.append(f"- `{name}`: {desc[:80]}")
    else:
        out.append("- (none)")
    out.append("")

    # --- Output patterns ---
    out.append("## Detected Patterns\n")
    pc = 0

    if repeated_cmds:
        out.append("### Repeated Commands\n")
        for cmd, sids in sorted(repeated_cmds.items(), key=lambda x: -len(x[1]))[:10]:
            pc += 1
            out.append(f"- `{cmd}` — {len(sids)} sessions")
        out.append("")

    if repeated_ngrams:
        out.append("### Command Sequences\n")
        for gram, sids in sorted(repeated_ngrams.items(), key=lambda x: -len(x[1]))[:8]:
            pc += 1
            steps = " → ".join(f"{t}({k[:30]})" for t, k in gram)
            out.append(f"- [{len(sids)} sessions] {steps}")
        out.append("")

    if repeated_wf:
        out.append("### Workflow Patterns\n")
        for name, sids in sorted(repeated_wf.items(), key=lambda x: -len(x[1])):
            pc += 1
            out.append(f"- **{name}** — {len(sids)} sessions")
        out.append("")

    if pc == 0:
        out.append("No repeated patterns detected yet. Keep using Claude Code for a few more sessions.\n")

    # --- Summary ---
    out.append("## Summary\n")
    out.append(f"- {pc} patterns across {n_sessions} sessions")
    out.append(f"- {len(skills)} existing skills")
    if total > 50000:
        out.append(f"- Log has {total} entries — consider cleanup (keep 30,000)")
    out.append("")

    print("\n".join(out))


if __name__ == "__main__":
    main()
