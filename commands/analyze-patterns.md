Analyze `~/.claude/tool_logs/operations.jsonl` operation logs to identify repeated patterns across sessions and auto-generate reusable skills.

## Steps

### 1. Read logs

Read `~/.claude/tool_logs/operations.jsonl`. If the file doesn't exist or is empty, tell the user "Logs are still accumulating — try again after a few sessions" and stop. If over 3000 lines, read only the most recent 3000. Skip any malformed lines (incomplete JSON from concurrent writes or rotation) — do not fail on them.

### 2. Statistics overview

Provide basic statistics:
- Total records, number of sessions (unique `sid`), time span
- Tool usage frequency TOP 5
- Top 10 most frequent Bash commands (extract `input.command` field)
- Top 5 working directories (`cwd` field)

### 3. Pattern detection

Group by `sid` (session ID) and look for these repeated patterns across different sessions:

**A. Repeated commands**
- Identical or highly similar Bash commands appearing in >= 3 different sessions
- Commands with the same structure but different arguments (e.g., `ssh host "cd /opt/X && ..."` where X varies)

**B. Command sequences**
- Groups of 2-5 operations that frequently appear together (e.g., edit config → build → deploy → check logs)
- Fixed-order tool call chains

**C. Workflow patterns**
- Deploy flows: rsync/scp + ssh restart + log checking
- Debug flows: grep error → read file → modify → test
- Data pipelines: collect → process → train → evaluate

**Ignore:**
- Operations that only appear in 1-2 sessions (if there are fewer than 3 sessions total, lower the threshold to 2)
- Isolated exploratory operations (standalone Read, Glob, Grep)
- Operations from the current analysis session itself

### 4. Output suggestions

For each identified pattern, output:

```
### Pattern: <pattern name>
- **Frequency**: appeared in N sessions
- **Typical steps**: describe specific steps
- **Parameterizable**: which parts change each time, can be replaced with $ARGUMENTS
- **Suggested skill filename**: <name>.md
- **Suggested skill content**:
(show complete .md file content)
```

### 5. Create skills

After showing all suggestions, ask the user which ones to create. Once confirmed:
- Write `.md` files to `~/.claude/commands/`
- Inform the user they can invoke them via `/<skill-name>`

### 6. Log maintenance

If the log exceeds 5000 lines, suggest cleanup (keep most recent 3000 lines). Execute cleanup after user confirms.

## Notes

- Generated skills use `$ARGUMENTS` for user-provided arguments
- Skill content should be clear instructions for Claude, not shell scripts
- Prioritize high-value patterns (operations that save the most time when automated)
- If a skill with the same name already exists in `~/.claude/commands/`, warn the user to avoid overwriting
- If no patterns are found, explain possible reasons (too few sessions, highly varied work, etc.) and suggest continuing to use Claude Code for more sessions before re-running
