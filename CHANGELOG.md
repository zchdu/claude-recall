# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [1.1.0] - 2026-03-02

### Added
- **Existing skill deduplication**: Before suggesting new skills, scans all existing skills in `~/.claude/commands/` and compares detected patterns against their functionality
  - Already covered patterns are skipped entirely
  - Partially overlapping patterns suggest updating existing skills instead of creating duplicates
  - Each suggestion now shows overlap level and recommended action
- Support for updating existing skills (not just creating new ones)

### Changed
- Log maintenance threshold raised from 5,000 to 50,000 lines (cleanup keeps 30,000)

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
