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

### 3. Scan existing skills

Before detecting patterns, read all `.md` files in `~/.claude/commands/` to understand what skills already exist. For each file, note:
- Filename (skill name)
- What it does (purpose/workflow)
- Key operations it covers (e.g., specific commands, services, hosts)

Keep this inventory in memory for comparison in the next steps.

### 4. Pattern detection

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

### 5. Output suggestions

For each identified pattern, **first compare it against the existing skills inventory from Step 3**:

- **Already covered**: If an existing skill already handles this exact pattern (same operations, same targets), skip it entirely — do not suggest it
- **Partially overlapping**: If an existing skill covers similar operations but differs in scope or target (e.g., existing skill deploys service A, new pattern deploys service B with same steps), suggest **updating the existing skill** to be more generic/parameterized rather than creating a new one. Show the diff or proposed changes to the existing skill
- **New pattern**: If no existing skill covers this pattern, suggest creating a new skill

For each suggestion, output:

```
### Pattern: <pattern name>
- **Overlap**: [None / Partial overlap with `<existing-skill>.md` / Fully covered by `<existing-skill>.md`]
- **Recommendation**: [Create new skill / Update existing `<skill>.md` / Skip (already exists)]
- **Frequency**: appeared in N sessions
- **Typical steps**: describe specific steps
- **Parameterizable**: which parts change each time, can be replaced with $ARGUMENTS
- **Suggested skill filename**: <name>.md
- **Suggested skill content**:
(show complete .md file content, or show proposed changes to existing skill)
```

### 6. Create skills

After showing all suggestions, ask the user which ones to create or update. Once confirmed:
- For new skills: write `.md` files to `~/.claude/commands/`
- For updates to existing skills: modify the existing `.md` file
- Inform the user they can invoke them via `/<skill-name>`

### 7. Log maintenance

If the log exceeds 50000 lines, suggest cleanup (keep most recent 30000 lines). Execute cleanup after user confirms.

## Notes

- Generated skills use `$ARGUMENTS` for user-provided arguments
- Skill content should be clear instructions for Claude, not shell scripts
- Prioritize high-value patterns (operations that save the most time when automated)
- If no patterns are found, explain possible reasons (too few sessions, highly varied work, etc.) and suggest continuing to use Claude Code for more sessions before re-running
