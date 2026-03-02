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
 Python pre-analyzer crunches logs → Claude reads the summary (not raw logs)
          │
          ▼
 You pick which patterns to save as /skills
          │
          ▼
 New skills are written to ~/.claude/ — ready to use
```

**Three components, zero friction:**

| Component | What it does |
|-----------|-------------|
| `log-operations.py` | **PostToolUse hook** — silently appends a JSON summary after every tool call. Auto-rotates at 10 MB. |
| `pre-analyze.py` | **Python script** — crunches raw logs into structured summaries. ~80% token savings vs reading raw JSONL. |
| `analyze-patterns` | **Skill** — reads the pre-analyzed summary, detects patterns across 3+ sessions, generates reusable skill files. |

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

Each tool call produces one compact JSONL entry:

```json
{
  "ver": 2,
  "ts": "2026-03-02T09:50:10Z",
  "sid": "e0af7856-2df8-48",
  "tool": "Bash",
  "input": {"command": "npm test", "description": "Run tests"},
  "cwd": "/home/user/my-project",
  "tuid": "toolu_01ABcDeF12",
  "res": {"success": true, "exit_code": 0}
}
```

| Feature | Detail |
|---------|--------|
| **Format** | v2 — includes tool response summary (`res`) and tool use ID (`tuid`) |
| **Truncation** | Strings over 300 chars trimmed, responses summarized to 500 chars |
| **Rotation** | Auto-rotates at 10 MB, keeping the newer half |
| **Location** | `~/.claude/tool_logs/operations.jsonl` |

## What `/analyze-patterns` Does

| Step | Description |
|------|-------------|
| **1. Pre-analyze** | Python script crunches logs into statistics + patterns (~10 KB summary) |
| **2. Statistics** | Total records, session count, tool frequency top 5, most common commands and directories |
| **3. Pattern detection** | Finds repeated commands, sequences (2–3 steps), and workflow patterns across 3+ sessions |
| **4. Suggestions** | For each pattern: name, frequency, steps, parameterizable parts, and a ready-to-use `.md` skill |
| **5. Creation** | You choose which to save → written to `~/.claude/commands/` → immediately available |

## Example Output

```
=== Pre-analysis Summary ===
Records: 853 | Sessions: 12 | Span: 7d
Tool Frequency: Bash (321, 38%), Read (253, 30%), Edit (124, 15%)
Existing Skills: restart-dashboard, dashboard-logs

Detected Patterns:
  Repeated: `ssh kubao "cd /opt/X && ..."` — 5 sessions
  Sequence: Edit(config) → Bash(cargo build) → Bash(deploy) — 4 sessions

=== Pattern: Deploy to Production ===
- Overlap: None
- Recommendation: Create new skill
- Frequency: 4 sessions
- Steps: rsync → ssh restart → tail logs

Which patterns to save? > 1

✓ Created ~/.claude/commands/deploy-prod.md
  Invoke with: /deploy-prod
```

## Manual Installation

<details>
<summary>Click to expand manual steps</summary>

### 1. Copy files

```bash
mkdir -p ~/.claude/{hooks,scripts,skills/analyze-patterns}
cp hooks/log-operations.py ~/.claude/hooks/
cp scripts/pre-analyze.py ~/.claude/scripts/
cp skills/analyze-patterns/SKILL.md ~/.claude/skills/analyze-patterns/
chmod +x ~/.claude/hooks/log-operations.py ~/.claude/scripts/pre-analyze.py
```

### 2. Register the hook

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
│   └── log-operations.py       # PostToolUse hook (v2 format)
├── scripts/
│   └── pre-analyze.py          # Log pre-analyzer
├── skills/
│   └── analyze-patterns/
│       └── SKILL.md            # /analyze-patterns skill
├── commands/
│   └── analyze-patterns.md     # Legacy skill (backward compat)
├── tool_logs/
│   └── operations.jsonl        # Auto-generated log
└── settings.json               # Hook registration
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

File contents and diffs are truncated to 300 characters. Tool responses are summarized to 500 characters (key fields only). You can review `~/.claude/tool_logs/operations.jsonl` at any time.
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

Run `./uninstall.sh`. It removes all components while preserving your other settings.
</details>

## Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) with hooks support
- Python 3.8+

## Contributing

Contributions are welcome. Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

[MIT](LICENSE)
