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

## Project settings (the lead fills these in once per repo)
- Full test suite, from clean: `<TEST_COMMAND>`
- Lint: `<LINT_COMMAND>`
- Static analysis: `<STATIC_ANALYSIS_COMMAND>`
- Ready-for-QA status in Intrackr: `<READY_FOR_QA_STATUS>`
Use exactly these commands wherever this skill says "full suite", "lint" or "static analysis". If a placeholder above is still unfilled, say so and ask the developer before Phase 0 step 4.

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
Delegate to the `planner` subagent with the full brief.md. It returns the plan: root cause/approach, acceptance criteria, scope (file + one-line reason each), explicitly out of scope, impact analysis (every caller of shared code and how it stays unchanged; DB/config/dependency changes; risk level + why), test plan (new unit tests, existing tests to run, manual steps for the developer), rollback, self-critique, open questions.
Save it as `.claude/task/$task/plan.md` and as the draft PR description. Do not post it to Intrackr. If the plan touches more than ~5 files or any shared helper, propose a split with `add_subtask` before presenting it. Put any open questions to the developer with the plan.
GATE 2: wait for "approved" or an edit. Apply edits to plan.md before coding.

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
