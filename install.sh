#!/usr/bin/env bash
# Installs the Intrackr task workflow into a target repo.
#
# Usage:
#   ./install.sh /path/to/repo [--server NAME] [--qa-status NAME] \
#       [--test CMD] [--lint CMD] [--static CMD]
#
#   --server     MCP server name as shown by /mcp (default: intrackr-developer)
#   --qa-status  Ready-for-QA status name in Intrackr (default: review)
#   --test       Full test suite command
#   --lint       Lint command
#   --static     Static analysis command
#
# Everything is copied; nothing in the target repo is deleted. The CLAUDE.md
# snippet is appended once. An existing .claude/settings.json is merged with jq.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
target="${1:-}"
[[ -n "$target" && -d "$target" ]] || { echo "usage: $0 /path/to/repo [options]" >&2; exit 1; }
shift

server="intrackr-developer"; qa="review"; test_cmd=""; lint_cmd=""; static_cmd=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --server)    server="$2"; shift 2 ;;
    --qa-status) qa="$2"; shift 2 ;;
    --test)      test_cmd="$2"; shift 2 ;;
    --lint)      lint_cmd="$2"; shift 2 ;;
    --static)    static_cmd="$2"; shift 2 ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
done

command -v jq >/dev/null || { echo "jq is required (the done-blocking hook uses it)." >&2; exit 1; }

cd "$target"
mkdir -p .claude/skills/intrackr-task .claude/agents

# Skill, with placeholders filled where values were given.
skill=".claude/skills/intrackr-task/SKILL.md"
cp "$here/.claude/skills/intrackr-task/SKILL.md" "$skill"
fill() { # fill PLACEHOLDER VALUE FILE
  [[ -n "$2" ]] || return 0
  python3 - "$1" "$2" "$3" <<'PY'
import sys, pathlib
ph, val, path = sys.argv[1:]
p = pathlib.Path(path); p.write_text(p.read_text().replace(ph, val))
PY
}
fill "<TEST_COMMAND>" "$test_cmd" "$skill"
fill "<LINT_COMMAND>" "$lint_cmd" "$skill"
fill "<STATIC_ANALYSIS_COMMAND>" "$static_cmd" "$skill"
fill "<READY_FOR_QA_STATUS>" "$qa" "$skill"

# Agents.
cp "$here/.claude/agents/scout.md" "$here/.claude/agents/planner.md" "$here/.claude/agents/task-reviewer.md" .claude/agents/

# Hook: merge into existing settings.json or create it.
hook_json="$(jq --arg m "mcp__${server}__update_task" '.hooks.PreToolUse[0].matcher = $m' "$here/.claude/settings.json")"
if [[ -f .claude/settings.json ]]; then
  merged="$(jq -s '
    .[0] as $cur | .[1] as $new |
    $cur | .hooks.PreToolUse = ((($cur.hooks.PreToolUse // []) | map(select(.matcher != $new.hooks.PreToolUse[0].matcher))) + $new.hooks.PreToolUse)
  ' .claude/settings.json <(echo "$hook_json"))"
  echo "$merged" > .claude/settings.json
else
  echo "$hook_json" > .claude/settings.json
fi

# CLAUDE.md pointer (or AGENTS.md if that is all the repo has).
memory="CLAUDE.md"
[[ ! -f CLAUDE.md && -f AGENTS.md ]] && memory="AGENTS.md"
if ! grep -q 'intrackr-task' "$memory" 2>/dev/null; then
  cat "$here/CLAUDE.md.snippet" >> "$memory"
fi

# gitignore.
grep -qx '.claude/task/' .gitignore 2>/dev/null || echo '.claude/task/' >> .gitignore

echo "Installed into $target"
echo "  $skill"
echo "  .claude/agents/{scout,planner,task-reviewer}.md"
echo "  .claude/settings.json  (hook matcher: mcp__${server}__update_task)"
echo "  $memory  (pointer appended)"
echo "  .gitignore  (.claude/task/)"
if grep -q '<[A-Z_]*>' "$skill"; then
  echo
  echo "Still to fill in $skill:"
  grep -o '<[A-Z_]*>' "$skill" | sort -u | sed 's/^/  /'
fi
echo
echo "Next: run /context and /agents in a fresh Claude Code session, then commit."
