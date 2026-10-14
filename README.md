# Intrackr task workflow for Claude Code

A gated, test-first workflow that Claude Code follows on every [Intrackr](https://intrackr.com) task. Claude does the work; the developer approves at four gates, reviews the diff, tests manually and ticks a checklist Claude produces with evidence under every item.

Seven phases: pick up, understand, plan, implement, test, review, hand off. Nothing moves to the next phase until the developer has signed off on the current one. The full workflow, the reasoning behind it and the Definition of Done are in [Developer-Workflow.md](Developer-Workflow.md).

## What is in the package

| File | Purpose |
| --- | --- |
| `Developer-Workflow.md` | The full workflow: phases, gates, who does what, and the source of every file below |
| `.claude/skills/intrackr-task/SKILL.md` | The orchestrating skill. Auto-triggers on a task id or "pick up"; also `/intrackr-task <id>` |
| `.claude/agents/scout.md` | Sonnet, read-only: repro, code path, blast radius, test inventory |
| `.claude/agents/planner.md` | Fable, plan mode: writes the plan document |
| `.claude/agents/task-reviewer.md` | Fable, read-only: adversarial review of the diff against the plan |
| `CLAUDE.md.snippet` | Pointer to the skill plus this repo's test, lint and static-analysis commands; appended to the target repo's `CLAUDE.md` |
| `.claude/settings.json` | PreToolUse hook that blocks marking a task `done` |
| `install.sh` | Installs into a repo or into `~/.claude`, and fills the CLAUDE.md commands |

Requirements: Claude Code, the Intrackr MCP server configured for each developer (below), and `jq` on each developer's machine (the hook uses it).

## Connect Claude Code to Intrackr (every developer, once)

Each developer adds the Intrackr MCP server to their own Claude Code config with their own token. Do this in user scope so the token never lands in the repo:

```bash
claude mcp add --transport http --scope user intrackr-developer \
  https://intrackr.doorloom.com/mcp/intrackr \
  --header "Authorization: Bearer <your-intrackr-token>"
```

Or paste the equivalent into the `mcpServers` section of `~/.claude.json`:

```json
{
  "intrackr-developer": {
    "url": "https://intrackr.doorloom.com/mcp/intrackr",
    "headers": {
      "Authorization": "Bearer <your-intrackr-token>"
    }
  }
}
```

Run `/mcp` in Claude Code to confirm it is connected. The server name `intrackr-developer` is what the hook matches on; if you name it differently, pass `--server <name>` to the installer.

If you prefer to commit the server definition so nobody has to add it by hand, put it in the repo's `.mcp.json` with the token read from an environment variable, and keep the real token in each developer's shell:

```json
{
  "mcpServers": {
    "intrackr-developer": {
      "url": "https://intrackr.doorloom.com/mcp/intrackr",
      "headers": {
        "Authorization": "Bearer ${INTRACKR_TOKEN}"
      }
    }
  }
}
```

## Install

The skill is stack-agnostic: it never contains test commands. Each repo's `CLAUDE.md` lists its own test, lint and static-analysis commands and the skill reads them from there. That gives two ways to install.

### Option A: per repo (recommended for teams)

The lead installs once; the files are committed, so every developer gets the workflow on the next `git pull`.

```bash
git clone https://github.com/pawan1793/intrackr-task-skill.git
cd intrackr-task-skill
./install.sh /path/to/your/repo \
  --test "npm test" \
  --lint "npm run lint" \
  --static "npx tsc --noEmit"
```

Use whatever your stack runs: `pytest` / `ruff check .` / `mypy .`, `composer test` / `composer lint` / `composer analyse`, `go test ./...` / `golangci-lint run`, and so on. Leave a flag out and the script tells you which placeholder in CLAUDE.md is still unfilled. `--server` overrides the MCP server name (default `intrackr-developer`).

Nothing in the target repo is deleted: an existing `.claude/settings.json` is merged, the CLAUDE.md block is appended once, and `.claude/task/` is added to `.gitignore`.

### Option B: once per machine

Installs the skill, agents and hook into `~/.claude`, where they apply to every repo on that machine. Each repo then only needs the CLAUDE.md block with its commands.

```bash
./install.sh --global
./install.sh /path/to/repo-one --claude-md-only --test "npm test" --lint "npm run lint" --static "npx tsc --noEmit"
./install.sh /path/to/repo-two --claude-md-only --test "pytest" --lint "ruff check ." --static "mypy ."
```

Option B is simpler for a solo developer. Option A is better for a team because the hook and the reviewer travel with the repo and changes to them go through pull requests.

### By hand

1. Create the folders `.claude/skills/intrackr-task/` and `.claude/agents/` (in the repo, or in `~/.claude` for a machine-wide install).
2. Copy `SKILL.md`, `scout.md`, `planner.md` and `task-reviewer.md` into them exactly as they are, frontmatter first line `---`.
3. Append `CLAUDE.md.snippet` to the repo's `CLAUDE.md` (create it if missing) and replace the three command placeholders with this repo's commands. If the repo has only an `AGENTS.md`, put the lines there instead; if it has both, CLAUDE.md wins.
4. Copy the hook from `.claude/settings.json` into the repo's `.claude/settings.json` or `~/.claude/settings.json`. The matcher expects the server to be named `intrackr-developer`; run `/mcp` and change it if yours differs.
5. Add `.claude/task/` to `.gitignore`.

Then, either way: commit what lives in the repo. Protect `main`: PR required, non-author approval, green CI running the full suite.

## Verify

- New session, run `/context`: `CLAUDE.md` under Memory files, `intrackr-task` under skills.
- `/agents`: scout, planner, task-reviewer listed.
- `/model`: confirm `fable`, `opus`, `sonnet` are available on your plan. If `fable` is not, change `model:` in `planner.md` and `task-reviewer.md` to `opus`. If the main session itself runs on Fable, set the reviewer to `opus` so implementer and reviewer stay different models.
- Smoke test: type `pick up task <id>`. Claude should move the task to `in_progress`, delegate to scout, post an Understanding brief and stop. If it starts editing files, use `/intrackr-task <id>` explicitly and tighten the skill description.

## Daily use (developer)

1. Fresh session in the right repo. Type `/intrackr-task <id>`.
2. Gate 1: read the Understanding brief. Reply `approved` or correct it.
3. Gate 2: read the plan's scope list, impact analysis and manual steps. Reply `approved` or edit it. Medium/high risk: get the lead's thumbs-up first.
4. Claude implements, tests, runs the reviewer and posts the checklist with evidence.
5. Gate 3: read the diff file by file, follow the manual test script in the app, click through the regression spots, tick each checklist item against its evidence. Send back anything unticked. Reply `all ticked`.
6. Open the PR for peer review. Merge after approval and green CI.
7. Gate 4: reply `hand off`. Claude posts the tester comment and sets the QA status. Never mark the task `done` yourself until QA passes.

If Claude drifts mid-task (long session, compaction), type `/intrackr-task <id>` again to reload the workflow.

Useful follow-ups during Gate 3:

- `Why is <file> in the diff?`
- `Show me the test that proves acceptance criterion 2.`
- `Revert the fix and show me the new tests failing.`
- `List every caller of <function> and the test that covers each.`
- `Run the task-reviewer again on the latest diff.`

## Rules that are not optional

- One task per session. No drive-by edits; anything else noticed becomes a new Intrackr task.
- Every change ships with tests Claude wrote and the full suite green from clean.
- The checklist comes from Claude with evidence; an item without evidence stays unticked.
- Claude never marks a task `done`. The hook enforces this; the skill and CLAUDE.md only ask for it.
- Small tasks go through the same gates.
- Run Intrackr work in the default or plan permission mode, not `bypassPermissions`.
- Keep the Intrackr MCP token in the developer's own config, never in a committed `.mcp.json`.

## Changing the workflow

The skill, agents and hook are code. Changes go through a pull request reviewed by the lead. Run `/doctor prompt-audit` after any change to catch contradictions between CLAUDE.md and the skill.

## Measuring

Two weeks after rollout, count per task: QA reopens, bugs filed against unrelated features within a week of merge, and out-of-scope files caught at Gate 3. If these are not falling, Gate 3 is being rubber-stamped.

## License

MIT. See [LICENSE](LICENSE).
