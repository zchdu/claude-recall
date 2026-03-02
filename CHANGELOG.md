# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [0.1.0] - 2026-03-02

### Added
- `log-operations.py` PostToolUse hook — silently logs every Claude Code tool call to `~/.claude/tool_logs/operations.jsonl`
  - Truncates large values (file contents, diffs) to keep logs compact
  - Auto-rotates when log exceeds 10 MB (keeps newer half)
  - Advisory file locking for safe concurrent multi-session writes
- `analyze-patterns.md` skill — analyzes logs to identify repeated workflows and generates reusable skills
  - Statistics overview (tool frequency, top commands, working directories)
  - Pattern detection (repeated commands, command sequences, workflow patterns)
  - Interactive skill creation with conflict detection
- `analyze-patterns.zh-CN.md` — Chinese translation of the analysis skill
- `install.sh` — automated installer (copies hook + skill, registers hook in settings.json)
- `uninstall.sh` — clean uninstaller (removes hook + skill + logs, cleans settings.json)
- Project documentation: README (English), README.zh-CN (Chinese), CONTRIBUTING guide
- GitHub issue templates for bug reports and feature requests
