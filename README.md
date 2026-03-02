<p align="center">
  <img src="assets/logo.svg" width="120" alt="Claude Recall">
  <h1 align="center">Claude Recall</h1>
  <p align="center">
    <strong>Turn your repetitive Claude Code workflows into reusable skills — automatically.</strong>
  </p>
  <p align="center">
    <a href="README.zh-CN.md">中文文档</a> &bull; <a href="#quick-start">Quick Start</a> &bull; <a href="#faq">FAQ</a>
  </p>
  <p align="center">
    <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License: MIT"></a>
    <a href="https://www.python.org/"><img src="https://img.shields.io/badge/Python-3.8%2B-3776AB.svg" alt="Python 3.8+"></a>
    <a href="https://docs.anthropic.com/en/docs/claude-code"><img src="https://img.shields.io/badge/Claude%20Code-hooks-blueviolet.svg" alt="Claude Code"></a>
  </p>
</p>

---

You use Claude Code every day. You deploy the same way, debug the same way, restart dev servers the same way. **Claude Recall** watches silently, finds those repeated workflows, and turns them into reusable skills you can invoke forever.

## How It Works

```
 You use Claude Code normally
          │
          ▼
 [Hook] log-operations.py silently records every tool call
          │
          ▼
 After a few sessions, you run /analyze-patterns
          │
          ▼
 Claude reads the logs, finds repeated multi-step workflows
          │
          ▼
 You pick which patterns to save as /skills
          │
          ▼
 New skills are written to ~/.claude/commands/ — ready to use
```

**Two components, zero friction:**

| Component | What it does |
|-----------|-------------|
| `log-operations.py` | **PostToolUse hook** — silently appends a one-line JSON summary after every tool call. Truncates large values, auto-rotates at 10 MB. |
| `analyze-patterns.md` | **Skill** — reads the accumulated logs, groups by session, detects commands/sequences/workflows appearing in 3+ sessions, and generates reusable skill files. |

## Quick Start

```bash
git clone https://github.com/zchdu/claude-recall.git
cd claude-recall
./install.sh
```

That's it. Use Claude Code normally for a few sessions, then run:

```
/analyze-patterns
```

## What Gets Logged

Each tool call produces one compact JSONL entry (~100 bytes):

```json
{
  "ts": "2026-03-02T09:50:10Z",
  "sid": "e0af7856-2df8-48",
  "tool": "Bash",
  "input": {"command": "npm test", "description": "Run tests"},
  "cwd": "/home/user/my-project"
}
```

| Feature | Detail |
|---------|--------|
| **Truncation** | Strings over 300 chars are trimmed (head 200 + tail 50) |
| **Rotation** | Auto-rotates at 10 MB, keeping the newer half |
| **Location** | `~/.claude/tool_logs/operations.jsonl` |

## What `/analyze-patterns` Does

| Step | Description |
|------|-------------|
| **1. Statistics** | Total records, session count, tool frequency top 5, most common commands and directories |
| **2. Pattern detection** | Finds repeated commands, sequences (2–5 steps), and workflow patterns across 3+ sessions |
| **3. Suggestions** | For each pattern: name, frequency, steps, parameterizable parts, and a ready-to-use `.md` skill |
| **4. Creation** | You choose which to save → written to `~/.claude/commands/` → immediately available |

## Example Output

Here's what `/analyze-patterns` produces after ~10 sessions:

```
=== Statistics ===
Total records: 853 | Sessions: 12 | Time span: 7 days
Tool frequency: Bash (321), Read (253), Edit (124), Write (39), Glob (23)

=== Existing Skills ===
Found 2 skills in ~/.claude/commands/:
  - restart-dashboard.md (kill → start → verify dashboard)
  - dashboard-logs.md (view logs with keyword filter)

=== Pattern: Dev Server Restart ===
- Overlap: Fully covered by restart-dashboard.md
- Recommendation: Skip (already exists)
- Frequency: appeared in 5 sessions

=== Pattern: Deploy to Production ===
- Overlap: None
- Recommendation: Create new skill
- Frequency: appeared in 4 sessions
- Typical steps: rsync → ssh restart service → tail logs
- Suggested skill: deploy-prod.md

Which patterns would you like to save as skills? (comma-separated numbers)
> 2

✓ Created ~/.claude/commands/deploy-prod.md
  Invoke with: /deploy-prod
```

## Manual Installation

<details>
<summary>Click to expand manual steps</summary>

### 1. Copy the hook

```bash
mkdir -p ~/.claude/hooks
cp hooks/log-operations.py ~/.claude/hooks/
chmod +x ~/.claude/hooks/log-operations.py
```

### 2. Copy the skill

```bash
mkdir -p ~/.claude/commands
cp commands/analyze-patterns.md ~/.claude/commands/
```

### 3. Register the hook

Add this to your `~/.claude/settings.json`:

```json
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
```

> If you already have a `hooks` section, merge the `PostToolUse` entry into it.

</details>

## File Structure

```
~/.claude/
├── hooks/
│   └── log-operations.py      # PostToolUse hook (data collection)
├── commands/
│   └── analyze-patterns.md    # /analyze-patterns skill
├── tool_logs/
│   └── operations.jsonl       # Auto-generated log (created on first use)
└── settings.json              # Hook registration
```

## FAQ

<details>
<summary><strong>Does it slow down Claude Code?</strong></summary>

No. The hook runs with a 5-second timeout and typically finishes in under 10 ms. It is a single JSON append.
</details>

<details>
<summary><strong>How much disk space does it use?</strong></summary>

The log auto-rotates at 10 MB. Typical usage produces roughly 1 MB per week.
</details>

<details>
<summary><strong>Does it capture sensitive data?</strong></summary>

File contents and diffs are truncated to 300 characters. The log records tool names, commands, and file paths. You can review `~/.claude/tool_logs/operations.jsonl` at any time.
</details>

<details>
<summary><strong>Can I log only specific tools?</strong></summary>

Yes. Change the `matcher` field in `settings.json`. For example, `"matcher": "Bash|Edit"` logs only Bash and Edit calls.
</details>

<details>
<summary><strong>What if I already have a settings.json?</strong></summary>

`install.sh` detects existing settings and safely merges the hook config without overwriting your file.
</details>

<details>
<summary><strong>How do I uninstall?</strong></summary>

Run `./uninstall.sh`, or manually remove `~/.claude/hooks/log-operations.py`, `~/.claude/commands/analyze-patterns.md`, and the `PostToolUse` hook entry from `~/.claude/settings.json`.
</details>

## Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) with hooks support
- Python 3.8+

## Contributing

Contributions are welcome. Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

[MIT](LICENSE)
