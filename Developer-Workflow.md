# Developer Workflow: Intrackr Tasks with Claude Code

Oct 13, 2026 · @Doorloom

Claude Code does the work on every Intrackr task in seven phases: pick up, understand, plan, implement, test, review, hand off. The developer does four things only: approve the plan, review the file changes, test manually in the app, and tick the checklist Claude produces. Nothing moves to the next phase until the developer has signed off on the current one.

## Why this workflow exists

Tasks are being closed by pointing Claude Code at an Intrackr ticket and accepting whatever comes back. The fix lands in files it did not need to touch, nothing proves the old behaviour still works, and an unrelated feature breaks a day later. This workflow forces Claude to show its thinking at four gates, so the developer can check it in minutes without doing the work themselves.

**Who does what**

| Step | Claude Code does | Developer does |
| --- | --- | --- |
| Pick up | Moves task to `in_progress`, creates branch | Chooses the task, gives Claude the id |
| Understand | Reads task, comments, screenshots; scout subagent reproduces and maps every caller of touched code | Reads the brief; corrects anything wrong (Gate 1) |
| Plan | Planner subagent writes scope, out-of-scope, impact analysis, test plan, rollback | Approves or edits the plan (Gate 2) |
| Implement | Changes only the files in scope; small commits | Nothing |
| Test | Writes unit + regression tests; runs full suite; reports counts | Nothing |
| Review | Task-reviewer subagent reviews the diff; Claude fixes blocking findings and produces the checklist with evidence per item | Reviews the diff file by file; tests manually in the app; ticks each item (Gate 3) |
| Hand off | Posts tester-facing comment; sets QA status | Says go (Gate 4); never marks `done` |

**Non-negotiable rules**

1. Claude reads before it writes: task, every comment, every screenshot, and the code path, before any file changes.
2. Claude plans before it codes, and the developer approves the plan. The plan lives in the draft PR description, not on the Intrackr task.
3. Scope is the task, not the file. Claude changes only what the plan lists. Anything else it notices becomes a new Intrackr task, never a drive-by edit.
4. Every change ships with tests Claude wrote: new behaviour gets new unit tests, every touched file and every caller has its tests run, the full suite passes.
5. The checklist comes from Claude, with evidence under every item. The developer ticks it only after reading the diff and testing manually; an item without evidence stays unticked.
6. Claude never marks a task `done`. Only a human moves a task to `done`, and only after QA.
7. Intrackr comments are written for the tester: what changed and how to verify it in the app. No branch names, commit hashes, PR numbers or file paths.

## Phase 0: Pick up the task

The developer chooses one task and hands Claude the id; Claude does the rest.

**Developer**

1. Ask Claude to list your pending work (`list_tasks`, `assigned_to_me` + `developer_pending`).
2. Pick one task: highest priority, or the one your lead named. Never two at once.
3. Open the right repo for that project and start a fresh Claude Code session with the task id.

**Claude**

1. `get_task` by id (never by title search). Confirm the project matches the git repo name via `list_projects`; stop and say so if it does not.
2. If status is `reopen`, read the reopen comment first and treat the previous fix as part of the problem.
3. `update_task` to `in_progress`.
4. Create a branch named after the task, for example `task/356-login-redirect`. One task, one branch, one PR.
5. Run the full test suite once and save the result as the baseline before anything changes.

## Phase 1: Understand

Claude produces an **Understanding brief** before any file changes, delegating the investigation to the read-only scout subagent (Sonnet); the developer reads it and corrects anything that does not match reality (Gate 1).

**Claude does**

- Reads the full task with `get_task` and every comment with `get_task_comments`, including replies. The latest comment wins over the description.
- Looks at every embedded screenshot and describes what each shows. Downloads and reads attached logs with `download_task_attachment`.
- Writes the acceptance criteria as a short list. If the task does not say how success is verified, it asks the developer rather than guessing.
- For a bug: reproduces it, with a failing test where possible. For a feature: finds the closest existing feature and reads it end to end (route, controller, service, model, view, test).
- Traces the code path from the entry point (route, command, job, event) to the data layer and lists every file on it.
- For every function, class, event, scope, config key and database column it expects to touch, searches for every other usage in the codebase. This list is the blast radius.
- Lists the existing tests covering those files and the behaviours that have none.
- Flags stop signals: fix needs a shared helper, base class, migration, config or package change; task and comments disagree; the repro shows a different bug than reported.

**Understanding brief format** (Claude posts this in chat, no edits made)

```markdown
Problem in two sentences
Acceptance criteria: - [ ] ...
Code path: entry -> ... -> data (files listed)
Blast radius: each touched symbol and everyone who calls it
Existing tests / gaps
Unsure about: ...
Stop signals: none / ...
```

**Developer: Gate 1**

- Read the brief. Does the problem statement match what the reporter meant? Is the blast radius complete as far as you know?
- Reply "approved" or correct it. Claude does not plan until you do.

## Phase 2: Plan

Claude switches the session into plan mode, delegates the plan to the planner subagent (Fable, plan mode, no file edits) and shows it on Claude Code's plan-approval screen; the developer approves it there before any code is written (Gate 2). Only the approved plan is saved, as the draft PR description. The plan is the contract the review checklist is built from. It is not posted to Intrackr.

**Claude writes**

```markdown
**Root cause / approach**
One paragraph: what is actually wrong, or how the feature will work.

**Acceptance criteria**
- [ ] ...

**Scope: files that will change**
- path/to/File.php — one-line reason

**Explicitly out of scope**
- Things noticed but not touched (each becomes its own Intrackr task)

**Impact analysis**
- Shared code touched: yes/no. If yes, every caller listed and how each stays unchanged.
- Database / config / dependency changes: yes/no.
- Risk: low / medium / high, and why.

**Test plan**
- New unit tests: behaviour A, behaviour B, edge case C
- Existing tests to run: those covering every touched file plus every caller
- Manual steps the developer will follow in the app

**Rollback**
How to undo if it goes wrong in production.

**Self-critique**
What this could break; what was assumed.
```

**Plan rules Claude must follow**

1. Smallest change that meets the acceptance criteria. More than about five files or any shared helper: propose a split (`add_subtask`) instead of a bigger plan.
2. Every file in scope has a one-line reason; a file with no reason is not in scope.
3. Every shared symbol in scope has its callers listed. This is the step that stops the unrelated bug.
4. Prefer adding over changing: new method, optional parameter or flag, so existing callers are untouched.
5. Refactors are a separate task, done first on their own branch.

**Developer: Gate 2**

- Read the scope list: does every file belong? Would you expect a file that is missing?
- Read the impact analysis: do the listed callers match what you know of the app?
- Read the manual steps: could you follow them?
- Medium or high risk: get the lead's thumbs-up before approving. Then approve the plan on the plan-approval screen, or reject it and say what to change; Claude revises and shows it again. Claude does not code until you approve.

## Phase 3: Implement

Claude implements only the approved plan; the diff matches the scope list file for file.

**Claude does**

1. For a bug, writes the failing test that reproduces it first, watches it fail for the right reason, then fixes.
2. Edits only files on the scope list. If a change needs another file, it stops and asks; the plan is updated only with the developer's approval.
3. Commits in small steps, one logical change each, message prefixed with the task id.
4. No opportunistic edits: no reformatting untouched lines, no renames for taste, no removing "unused" code, no package upgrades, no fixing other bugs seen. Each becomes a new Intrackr task (`create_task`, status `todo`), listed in the final report.
5. Shared functions keep their signature and default behaviour; new behaviour goes behind a new method or optional parameter.
6. Database or config changes are reversible, defaults keep existing rows valid, and the change is noted for the handoff comment.
7. Runs `git diff --stat` against the scope list and reports any mismatch before moving to tests.

**Developer**

Nothing yet. Review happens in Phase 5 with the full diff and the checklist.

## Phase 4: Test

Claude writes and runs three layers of tests and reports the counts against the Phase 0 baseline. The developer does nothing here; the manual test comes in Phase 5.

**Layer 1: unit tests for the change**

For every unit added or changed, Claude writes tests that fail if the change is reverted, covering:

- the happy path for each acceptance criterion
- every branch added or changed (each `if`, `switch`, early return)
- boundaries: empty, null, zero, maximum, duplicate, already-processed
- failure paths: invalid input, missing record, permission denied, external call fails
- for a bug: the exact reproduction from the task, named after it, for example `test_task_356_login_redirects_to_intended_url`

Test rules Claude follows: behaviour through the public interface, not private internals; one idea per test, named for what it proves; mock only external boundaries (HTTP, mail, queues, time), never the class under test or in-repo collaborators; and a revert check: temporarily revert the fix, confirm the new tests fail, restore it.

**Layer 2: regression tests for the blast radius**

- Runs every existing test covering a touched file, plus every test covering each caller from the impact analysis.
- Shared code with an untested caller: writes a characterisation test pinning that caller's current behaviour, then confirms it still passes after the change.
- Changed model, scope, event or column: runs the whole feature area's tests.
- Migrations: migrate, rollback, migrate again on a copy of realistic data.

**Layer 3: full suite**

- Full suite from clean, lint and static analysis all pass. No test skipped, marked incomplete or deleted to get green; a test that must go is reported to the developer with the reason.
- Compares with the baseline: zero new failures, no fewer tests than before unless the plan says why.

**Test report Claude posts in chat**

```markdown
Baseline: N tests, F failing (pre-existing)
Now: N+M tests, 0 failing, M new
New tests: list with the behaviour each proves
Revert check: new tests fail with fix reverted: yes/no
Caller tests run: list
Skipped / deleted: none
```

## Phase 5: Review

Claude first sends the diff to the task-reviewer subagent (Fable, fresh context, read-only), fixes its blocking findings, then produces the review checklist with evidence under every item; the developer reviews the diff file by file, tests manually in the app, and ticks each item only when the evidence holds (Gate 3). Then a peer reviews.

**Claude produces** (pasted into the PR description under the plan)

```markdown
## Review checklist
- [ ] Every changed file is on the scope list
      Evidence: git diff --stat output vs scope list; 0 extra files
- [ ] Every acceptance criterion has a test
      Evidence: criterion -> test name, one line each
- [ ] No behaviour change for existing callers of shared code
      Evidence: each caller, its test file, pass/fail
- [ ] No formatting-only, rename-only or unrelated changes
      Evidence: files where only whitespace changed: none
- [ ] Failures are reported, not swallowed; no empty catch blocks
      Evidence: grep result for new try/catch
- [ ] Inputs validated at the boundary; no new SQL, mass-assignment or XSS surface
      Evidence: where validation sits, line references
- [ ] No secrets, debug output, commented-out code or TODOs left
      Evidence: grep result
- [ ] Migrations reversible and safe on existing data
      Evidence: migrate/rollback/migrate log, or N/A
- [ ] Full suite, lint, static analysis green from clean
      Evidence: counts from the test report
- [ ] Adversarial self-review done
      Evidence: the three biggest risks it found and how each is covered

## Manual test script for the developer
1. Go to ... as a ... user
2. Do ...
3. Expect ...
Regression spots to click through (from the impact analysis):
- Feature X, because it shares ...
```

**Developer: Gate 3**

1. Open the diff and read every file against the scope list. A file you do not understand the reason for is a question to Claude, not a tick.
2. Run the app and follow the manual test script exactly, then click through each regression spot.
3. Tick each checklist item only after checking its evidence. An item with no evidence, or evidence you cannot see, stays unticked and goes back to Claude.
4. Push back freely: "why this file", "show me the test for criterion 2", "revert and prove the test fails". Claude fixes and re-runs the full suite after any change.
5. All ticked and manual test passed: open the PR for peer review.

**Peer review**

1. PR title = task id + task title. Description = link to the Intrackr task, the plan, the test report and the ticked checklist.
2. Reviewer reads the task and plan first, then the diff. They check: does the diff do what the plan says and nothing more; are the callers in the impact analysis really safe; would the tests catch a regression.
3. Any change outside scope is a blocking comment, even if it is an improvement.
4. Review comments are resolved with code or a reply, never dismissed. Claude re-runs the full suite after review changes.
5. Merge only after approval and a green pipeline. No self-merge, including "tiny" fixes; those are where the unrelated bugs come from.

## Phase 6: Handoff

After merge, the developer says "hand off" (Gate 4) and Claude posts the tester-facing comment and sets the QA status. The status is never `done`.

**Claude does**

1. Posts the handoff comment with `add_comment`, @mentioning the QA assignee by exact username:

```markdown
**What changed**
Two or three sentences in product terms (what the user sees differently).

**How to verify**
1. Go to ... as a ... user
2. Do ...
3. Expect ...

**Also please check (regression)**
- Feature X still works because it shares the same ... (from the impact analysis)

**Not covered by this task**
- Deliberately left out, with the new task id

Tests: N passing, M new.
```

2. Attaches before/after screenshots with `upload_comment_attachment` where the change is visual.
3. `update_task`: sets the QA assignee if the task has none, sets status to the team's ready-for-QA state, leaves the assignee as the developer so a reopen comes straight back.
4. Creates one Intrackr task (`create_task`) for each out-of-scope finding from the plan: what was seen, where, why it was left out.

**Developer**

- Skim the comment once: would a tester be able to follow it without asking you anything? If not, tell Claude what is missing (`edit_comment` fixes the last comment).
- If QA reopens: start a new Claude session at Phase 1. Claude must redo the understanding and impact analysis; patching the previous fix without it is where the unrelated bug usually lands.

## What the developer types

With the skill committed, no long prompt is needed. The developer starts the task and answers at the gates; everything else is in the skill.

| Moment | What you type |
| --- | --- |
| Start | `/intrackr-task 356` (or `pick up task 356`; the slash form always works) |
| Gate 1 | `approved`, or the correction |
| Gate 2 | approve on the plan-approval screen, or reject with the edit |
| Gate 3 | the unticked items and why, then `all ticked` |
| Gate 4 | `hand off` |
| Claude drifts mid-task | `/intrackr-task 356` again to reload the workflow |

**Useful follow-ups during Gate 3**

- `Why is <file> in the diff?`
- `Show me the test that proves acceptance criterion 2.`
- `Revert the fix and show me the new tests failing.`
- `List every caller of <function> and the test that covers each.`
- `Run the task-reviewer again on the latest diff.`

## Make it automatic: project skill + CLAUDE.md + hook

Commit five things to each repo and the workflow runs itself whenever a developer mentions an Intrackr task: a project skill that orchestrates the procedure, three read-only subagents it delegates to (scout, planner, task-reviewer), a two-line pointer in CLAUDE.md, and a hook that hard-blocks marking a task done. The skill is the right home, not CLAUDE.md: Claude Code's docs say to keep CLAUDE.md to short always-on facts and move multi-step procedures into a skill, which loads only when triggered and survives compaction better. AGENTS.md is for repos shared with other coding agents; Claude reads it only when there is no CLAUDE.md, so pick one and stick to it.

**1. The skill: `.claude/skills/intrackr-task/SKILL.md`**

Claude invokes it automatically when a message matches the description, and developers can type `/intrackr-task 356`. Keep the most important rules near the top; after compaction only the first part of a skill is guaranteed to survive.

```markdown
---
name: intrackr-task
description: Gated workflow for any Intrackr task. Use whenever the user mentions an Intrackr task, a task id like #356, "work on task", "pick up", "fix this ticket", "start the next task", or asks to implement, resume or hand off anything tracked in Intrackr. Claude does the work; the developer only approves at gates.
argument-hint: [task-id]
arguments: task
---

Work Intrackr task #$task using the gated workflow below. These are standing rules for the whole task, not one-time steps. You are the orchestrator: you delegate understanding to `scout`, planning to `planner` and review to `task-reviewer`, and you do implementation, testing and handoff yourself. Subagents start with no memory of this conversation, so every delegation message must carry what they need (task id, the brief, the plan, file paths).

## Hard rules (apply at every step)
- STOP at every GATE and wait for the developer's reply. Never continue past a gate on your own.
- Never set an Intrackr task to `done`. Only a human does that.
- Edit only files on the approved scope list. Need another file? Stop and ask.
- No reformatting, renames, cleanup, package upgrades or fixes outside the task. Log each as a new Intrackr task instead.
- Never skip, delete or mark-incomplete a test to get green. Report it and wait.
- Intrackr comments are for testers: no file paths, branch names, commit hashes or PR numbers.

## Project settings
- Test, lint and static-analysis commands: use exactly the ones this repo's CLAUDE.md lists under "Intrackr tasks". Wherever this skill says "full suite", "lint" or "static analysis", run those. If CLAUDE.md does not list them, ask the developer before Phase 0 step 4; never guess from the stack.
- Ready-for-QA status in Intrackr: `review`.

## Phase 0: Pick up (you)
1. `get_task` by id (never title search). `list_projects` and confirm the project matches this git repo; stop if not.
2. If status is `reopen`, read the reopen comment first; the previous fix is part of the problem.
3. `update_task` -> `in_progress`. Create branch `task/$task-<slug>`.
4. Run the full test suite once and record the baseline (count, pre-existing failures).
5. Read the task and every comment (`get_task_comments`), describe every screenshot, download attached logs. Write the acceptance criteria. Save all of it to `.claude/task/$task/brief.md`.

## Phase 1: Understand (scout) -> GATE 1
Delegate to the `scout` subagent with: the task id, the contents of brief.md, and the acceptance criteria. Ask it to reproduce the bug (failing test if possible) or read the nearest existing feature end to end, trace the code path from entry point to data layer, list every usage of every symbol likely to change (blast radius), list existing tests and gaps, and flag stop signals (shared helper, migration, config, package, task/comments disagree).
Append its report to brief.md and post the Understanding brief to the developer: problem in two sentences, acceptance criteria, code path, blast radius, tests/gaps, unsure about, stop signals.
GATE 1: wait for "approved" or a correction. Apply corrections to brief.md.

## Phase 2: Plan (planner) -> GATE 2
Call `EnterPlanMode` first. Then delegate to the `planner` subagent with the full brief.md. It returns the plan: root cause/approach, acceptance criteria, scope (file + one-line reason each), explicitly out of scope, impact analysis (every caller of shared code and how it stays unchanged; DB/config/dependency changes; risk level + why), test plan (new unit tests, existing tests to run, manual steps for the developer), rollback, self-critique, open questions.
If the plan touches more than ~5 files or any shared helper, put the proposed split (subtask titles and what each covers) at the top of the plan. If an open question would change the scope or approach, ask it with `AskUserQuestion` and fold the answer into the plan; leave the rest under Open questions.
GATE 2: call `ExitPlanMode` with the full plan, unabridged. That approval screen is the gate. If the developer rejects it with feedback, stay in plan mode, revise (re-delegate to `planner` if the approach changes) and call `ExitPlanMode` again. Only after approval: save the approved plan as `.claude/task/$task/plan.md` and as the draft PR description, and create any split with `add_subtask`. Do not post the plan to Intrackr. If `EnterPlanMode` is unavailable or declined, post the plan as a message and wait for "approved" or an edit instead.

## Phase 3: Implement (you)
Failing test first for bugs. Small commits prefixed `#$task`. Shared functions keep signature and default behaviour; prefer adding (new method/optional param) over changing. DB/config changes reversible with safe defaults. Finish with `git diff --stat` compared to the scope list in plan.md and report any mismatch.

## Phase 4: Test (you)
Unit tests for every behaviour added or changed: happy path per acceptance criterion, every branch, boundaries (empty, null, zero, max, duplicate, already-processed), failure paths, the task's exact repro named after it. Public interface only; mock only external boundaries. Revert the fix, confirm the new tests fail, restore. Run tests for every touched file and every caller from the impact analysis; add characterisation tests for untested callers. Migrations: migrate, rollback, migrate. Full suite, lint, static analysis from clean (delegate the noisy runs to `scout` and ask for failures only if output is large).
Post the test report: baseline vs now, new tests and what each proves, revert check result, caller tests run, skipped/deleted (must be none).

## Phase 5: Review (task-reviewer) -> GATE 3
Delegate to the `task-reviewer` subagent with the path to plan.md and the branch name. It returns findings by severity. Fix every Blocking finding, re-run the full suite, and re-run the reviewer if the diff changed materially. Then add to the PR description: the reviewer's findings and what was done about each, the review checklist with concrete evidence under every item (scope match, criterion->test map, caller safety, no unrelated changes, error handling, input validation, no leftovers, migrations, suite green), plus a numbered manual test script and regression spots for the developer.
GATE 3: wait while the developer reviews the diff, tests manually and ticks items. Fix what comes back and re-run the full suite after every change.

## Phase 6: Handoff (you, after "hand off")
`add_comment` @mentioning the QA assignee by exact username: what changed in product terms, numbered verify steps, regression checks, not covered, test counts. Attach before/after screenshots. `update_task`: QA assignee, ready-for-QA status (see Project settings), assignee stays the developer. `create_task` for each out-of-scope finding. Never `done`.
```

**2. The pointer: add to `CLAUDE.md`**

Keep CLAUDE.md short; the procedure lives in the skill. The pointer plus the repo's own commands is enough. The commands live here, not in the skill, so the same skill works for any stack and can also be installed once per machine:

```markdown
## Intrackr tasks
Any work on an Intrackr task (task id, "pick up", "fix ticket", "hand off") follows the `intrackr-task` skill. Stop at its gates; never mark a task done.
- Full test suite, from clean: `npm test`
- Lint: `npm run lint`
- Static analysis: `npx tsc --noEmit`
```

If the repo already has an AGENTS.md and no CLAUDE.md, put the same two lines in AGENTS.md instead. If it has both, Claude reads CLAUDE.md only, so the pointer must be there.

**3. The hard stop: a hook that blocks `done`**

CLAUDE.md and skills are guidance Claude can drift from; a hook is enforced by the client every time. This PreToolUse hook rejects any Intrackr `update_task` call whose status is `done`. Add it to `.claude/settings.json` so the whole team gets it; replace `intrackr-developer` in the matcher with the MCP server's actual name as shown by `/mcp` if yours differs.

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "mcp__intrackr-developer__update_task",
        "hooks": [
          {
            "type": "command",
            "command": "jq -e '.tool_input.status != \"done\"' > /dev/null || { echo 'Blocked: tasks are never marked done by Claude. A human closes the task after QA.' >&2; exit 2; }"
          }
        ]
      }
    ]
  }
}
```

Exit code 2 blocks the call and feeds the message back to Claude. Requires `jq` on the developer's machine. The same pattern can block `git push` to main or edits under a protected directory if you want more enforcement later.

**4. The three agents: `.claude/agents/scout.md`, `planner.md`, `task-reviewer.md`**

Each phase gets the model that suits it. Subagents start with a fresh context and only the tools their frontmatter allows, so they cannot drift into editing, and the main session (Opus) keeps implementation and testing together where shared context matters. Check `/model` for the aliases your plan allows; if `fable` is not available, use `opus` for planner and reviewer and keep the main session on `sonnet` or `opus`.

| Role | File | Model | Tools | Why this model |
| --- | --- | --- | --- | --- |
| Orchestrate, implement, test, hand off | main session | Opus | all | shared context across implement and test |
| Scout: repro, code path, blast radius, test inventory, noisy test runs | `scout.md` | Sonnet | read-only + Bash | high-volume grep and test output; keeps main context clean |
| Planner: scope, impact analysis, test plan | `planner.md` | Fable | read-only, plan mode | hardest reasoning in the task; output is a document |
| Reviewer: adversarial review of the diff against the plan | `task-reviewer.md` | Fable | read-only + Bash | strongest model, fresh eyes, different model from the implementer |

`scout.md`:

```markdown
---
name: scout
description: Read-only investigator for Intrackr tasks. Use in Phase 1 of the intrackr-task workflow to reproduce, trace the code path, map the blast radius and inventory tests; also for running noisy test suites and returning failures only.
tools: Read, Grep, Glob, Bash
model: sonnet
---

You investigate; you never edit. The task message gives you a task id, a brief and acceptance criteria. Return facts with file paths and line numbers, not opinions.

When asked to understand a task:
1. Reproduce: for a bug, find the failing path and, if possible, write the exact test invocation that would fail (do not create the file; describe it). For a feature, find the nearest existing feature and read it end to end: route, controller/handler, service, model, view, tests.
2. Code path: from the entry point (route, command, job, event) to the data layer. List every file on the path.
3. Blast radius: for every function, class, method, event, scope, config key and database column likely to change, grep the whole codebase for every other usage. List each caller with file:line. Say explicitly when a symbol has zero other callers.
4. Tests: list the existing test files covering the path and the callers; list behaviours with no tests.
5. Stop signals: shared helper or base class involved; migration, config or package change needed; task and comments disagree; the repro points at a different bug than reported.

When asked to run tests: run the exact command given, and return only the counts, the names of failing tests with their first error line, and anything skipped. No passing-test output.

Format: short headed sections, bullets, file:line everywhere. If you are unsure, say so under "Unsure".
```

`planner.md`:

```markdown
---
name: planner
description: Produces the implementation plan for an Intrackr task in Phase 2 of the intrackr-task workflow. Read-only; never edits. Input is the understanding brief; output is a plan document.
tools: Read, Grep, Glob, Bash
model: fable
permissionMode: plan
---

You write the plan for a change you will not implement. The task message contains the understanding brief (problem, acceptance criteria, code path, blast radius, tests and gaps). Read the referenced files yourself before deciding anything; verify the blast radius rather than trusting it.

Return exactly this document:

**Root cause / approach**: one paragraph.
**Acceptance criteria**: checklist.
**Scope**: every file that will change, each with a one-line reason. A file without a reason is out.
**Explicitly out of scope**: things noticed but not to be touched; each is a candidate Intrackr task.
**Impact analysis**: every shared function, class, event, scope or column touched, every caller of each, and how each caller stays unchanged (new method, optional parameter, default preserved). DB/config/dependency changes, yes or no. Risk: low / medium / high and why.
**Test plan**: new unit tests (behaviour, branch, boundary, failure path, the task's repro by name); existing tests to run (every touched file plus every caller); characterisation tests needed for untested callers; numbered manual steps a developer will follow in the app; regression spots to click through.
**Rollback**: how to undo in production.
**Self-critique**: what this could break, what you assumed, what a reviewer would push back on.
**Open questions**: anything only the developer or reporter can answer. Do not guess at these.

Rules: smallest change that meets the criteria; prefer adding over changing; refactors are a separate task; if the plan needs more than about five files or any shared helper, say so at the top and propose how to split it. You cannot ask the user questions; put them under Open questions.
```

`task-reviewer.md`:

```markdown
---
name: task-reviewer
description: Independent reviewer for Intrackr task diffs. Use in Phase 5 of the intrackr-task workflow, after tests pass and before the developer's review. Read-only.
tools: Read, Grep, Glob, Bash
model: fable
---

You are a demanding senior engineer reviewing a pull request you did not write. You have no memory of how the change was made; judge only what is in front of you. The task message gives you the branch and the path to the plan.

Start by reading the plan, then run `git diff main...HEAD --stat` and `git diff main...HEAD`.

Check, in this order:
1. Scope: every changed file is on the plan's scope list with its stated reason. Any file that is not is a Blocking finding, even if the change looks like an improvement.
2. Acceptance criteria: each criterion maps to at least one test that would fail if the fix were reverted. Name the test or report the gap.
3. Blast radius: for every shared function, class, event, scope or column touched, grep for every caller and confirm its behaviour is unchanged or covered by a test. Report each caller you checked.
4. Unrelated changes: whitespace-only, renames, removed "unused" code, dependency bumps, drive-by fixes.
5. Correctness and safety: swallowed errors, empty catch blocks, missing input validation, new SQL/mass-assignment/XSS surface, leftover debug output, TODOs, secrets.
6. Migrations and config: reversible, safe on existing rows, defaults preserved.
7. Tests: run the suite yourself and report counts; check that no test was skipped, deleted or weakened.

Report findings grouped as Blocking / Should fix / Suggestion, each with file:line, what is wrong, and what you would accept instead. Then give one-line answers to: What is most likely to break in production? What is untested? What would you reject this PR for? Do not praise; if a section has nothing, write "none found". You cannot edit files.
```

If the main session itself runs on Fable, set the reviewer to `opus` so implementer and reviewer stay different models. Subagents cannot ask the developer questions, which is why the planner returns Open questions for the main session to raise at Gate 2. Each subagent run spends its own tokens; the scout on Sonnet is the cheap one, planner and reviewer on Fable are the expensive ones and run once per task each (reviewer twice if the diff changes materially).

**Optional: hard scope enforcement.** If drive-by edits keep happening despite the rules, a `PreToolUse` hook on `Edit|Write` can compare the file path against a `.claude/scope.txt` that Claude writes at Gate 2 and block anything not listed. It is more setup and occasionally gets in the way (new test files must be in scope too), so start with the rules plus the reviewer and add this only if needed.

**5. Roll out and verify**

1. Commit `.claude/skills/intrackr-task/SKILL.md`, the three files in .claude/agents/, the CLAUDE.md lines and `.claude/settings.json` to each repo that has Intrackr tasks. Add .claude/task/ to .gitignore; the brief and plan files are per-developer scratch.
2. Each developer starts a fresh session and runs `/context`; `CLAUDE.md` should appear under Memory files and `intrackr-task` under skills; /agents should list scout, planner and task-reviewer.
3. Smoke test: type `pick up task 356` without the slash. Claude should move to `in_progress`, produce the Understanding brief and stop. If it starts editing files, tighten the skill description or have developers invoke `/intrackr-task 356` explicitly.
4. Run `/doctor prompt-audit` after any later edit to catch contradictions between CLAUDE.md and the skill.

[Claude Code docs: memory](https://code.claude.com/docs/en/memory.md) · [skills](https://code.claude.com/docs/en/skills.md)

## Gaps to close before rollout

Everything above runs on the developer's machine and can be skipped by a developer in a hurry. These six items make the workflow hold up in practice.

**1. CI and branch protection are the real last gate.** Hooks, skills and CLAUDE.md are local. Protect `main`: require a pull request, at least one approving review from someone other than the author, and a green status check that runs the full suite, lint and static analysis in CI. Nothing in this doc works if a developer can push to main.

**2. The test suite must exist and be trustworthy.** The whole workflow leans on "full suite green". Before rollout: document the exact test, lint and static-analysis commands in CLAUDE.md so Claude runs the right ones; fix or quarantine flaky tests, because a developer who learns to re-run until green will ignore real failures; and add a small always-on smoke suite for the flows that keep breaking (login, checkout, whatever the recent unrelated bugs hit).

**3. One task per session, and a clean one.** Start each task in a fresh session (`/clear` or a new window) so the previous task's context cannot leak into scope. Keep the Intrackr MCP token out of the repo; it lives in the developer's own config, never in `.mcp.json` committed to git.

**4. Permission mode.** Run in the default or plan permission mode for Intrackr work. `bypassPermissions` turns every tool prompt off, including the ones that give the developer a chance to notice an edit outside scope. The hooks still fire, but fewer eyes are on the work.

**5. Changes to the workflow go through review too.** The skill, the reviewer agent and the hook are code in the repo. A change to any of them is a pull request reviewed by the lead, not an edit on a branch. Run `/doctor prompt-audit` after each change.

**6. Measure it.** Two weeks after rollout, count per task: QA reopens, bugs filed against unrelated features within a week of merge, and files changed outside scope caught at Gate 3. If reopens and unrelated bugs are not dropping, the gates are being rubber-stamped; look at whether Gate 3 is actually being done against evidence.

**Small tasks are not exempt.** A one-line fix goes through the same gates; the developer can answer Gate 1 and Gate 2 in one reply when the brief and plan are both trivially right. The unrelated bugs this workflow exists to stop came from "tiny" changes.

## Definition of Done

A task is ready for QA only when every box is ticked by the developer, each against evidence Claude produced. A lead can reject the handoff for any unticked item.

- [ ] Gate 1: Understanding brief read and approved; blast radius listed
- [ ] Gate 2: Plan approved; every file in scope has a reason; every shared symbol has its callers listed
- [ ] Diff matches the scope list; no unrelated edits, refactors or formatting changes
- [ ] Every acceptance criterion has a unit test; new tests shown to fail with the fix reverted
- [ ] Tests run for every touched file and every caller; characterisation tests added where callers had none
- [ ] Full suite, lint and static analysis green from clean; no tests skipped or deleted
- [ ] Gate 3: diff reviewed file by file; manual test script followed in the app; regression spots clicked through; all checklist items ticked against evidence
- [ ] Peer review approved; pipeline green; merged
- [ ] Gate 4: tester-facing handoff comment posted; QA assignee set; status ready-for-QA, not `done`
- [ ] Out-of-scope findings logged as separate Intrackr tasks
