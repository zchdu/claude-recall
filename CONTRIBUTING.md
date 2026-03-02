# Contributing to Claude Recall

Thank you for your interest in contributing! This guide covers how to get involved.

## Reporting Issues

Before opening an issue, please:

1. Search [existing issues](../../issues) to avoid duplicates
2. Use the appropriate issue template (bug report or feature request)
3. Include your Python version (`python3 --version`) and OS

## Development Setup

```bash
# Clone the repo
git clone https://github.com/zchdu/claude-recall.git
cd claude-recall

# No dependencies to install — the hook uses only Python stdlib.
# Just make sure you have Python 3.8+.
python3 --version

# Run the install script to set up locally
./install.sh
```

### Project Structure

```
hooks/log-operations.py       # PostToolUse hook (data collection)
commands/analyze-patterns.md  # /analyze-patterns skill (English)
commands/analyze-patterns.zh-CN.md  # /analyze-patterns skill (Chinese)
install.sh                    # Installer
uninstall.sh                  # Uninstaller
```

## Pull Request Process

1. **Fork** the repository and create a branch from `main`.
2. Keep changes focused — one PR per feature or fix.
3. Update `CHANGELOG.md` under the `[Unreleased]` section.
4. If you modify `log-operations.py`:
   - Ensure it still works with Python 3.8+ and only uses the stdlib.
   - Verify the hook does not raise exceptions under any input (the blanket `try/except` in `main()` must remain).
   - Test manually: pipe sample JSON to stdin and confirm a valid JSONL line is appended.
5. If you modify `analyze-patterns.md`:
   - Keep the Chinese translation (`analyze-patterns.zh-CN.md`) in sync, or note in the PR that translation is needed.
6. Write a clear PR description explaining **what** changed and **why**.

## Coding Guidelines

- **Python hook**: stdlib only, no third-party packages. Must work on Python 3.8+.
- **Skill files (.md)**: Write clear, unambiguous instructions for Claude. Use imperative mood.
- **Shell scripts**: Use `set -euo pipefail`. Support both macOS and Linux.
- Keep the project minimal — avoid scope creep.

## Commit Messages

Use concise, descriptive messages. Examples:

```
Add file locking to prevent concurrent write corruption
Fix rotation losing last line when file ends without newline
Add Chinese translation for analyze-patterns skill
```

## Code of Conduct

Be respectful and constructive. We follow the [Contributor Covenant](https://www.contributor-covenant.org/version/2/1/code_of_conduct/).

## Questions?

Open a [discussion](../../discussions) or file an issue. We're happy to help!
