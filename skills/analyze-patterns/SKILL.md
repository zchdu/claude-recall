Analyze tool operation logs to identify repeated patterns across sessions and auto-generate reusable skills.

## Pre-analysis data

!`python3 $HOME/.claude/scripts/pre-analyze.py`

## Instructions

You have received a structured pre-analysis report above. Use it to evaluate patterns and make recommendations. Do NOT read the raw JSONL log file.

### 1. Review statistics

Briefly summarize the statistics: activity level, dominant tools, most active directories.

### 2. Scan existing skills

Read all `.md` files in `~/.claude/commands/` and all `SKILL.md` in `~/.claude/skills/*/` to understand what skills already exist.

### 3. Evaluate detected patterns

For each pattern, compare against existing skills:

- **Already covered** → Skip
- **Partially overlapping** → Suggest updating the existing skill
- **New pattern** → Suggest creating a new skill

For each actionable pattern, output:

```
### Pattern: <name>
- **Overlap**: [None / Partial with `<skill>` / Fully covered]
- **Recommendation**: [Create new / Update existing / Skip]
- **Frequency**: N sessions
- **Typical steps**: specific operations
- **Parameterizable**: what varies → use $ARGUMENTS
- **Suggested filename**: <name>.md
- **Suggested content**: (complete .md)
```

### 4. Create skills

Ask the user which to create/update. Write `.md` files to `~/.claude/commands/`.

### 5. Log maintenance

If the summary mentions log cleanup needed, offer to trim (keep 30,000 lines).

## Notes

- Generated skills use `$ARGUMENTS` for user-provided arguments
- Skill content should be clear instructions for Claude, not shell scripts
- Prioritize high-value patterns that save the most time
- If no patterns found, suggest using Claude Code for more sessions
