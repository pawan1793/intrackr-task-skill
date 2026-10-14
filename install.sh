#!/usr/bin/env bash
# Installs the Intrackr task workflow.
#
# Per repo (skill, agents and hook committed with the app):
#   ./install.sh /path/to/repo [--server NAME] [--test CMD] [--lint CMD] [--static CMD]
#
# Per machine (skill, agents and hook in ~/.claude, shared by every repo):
#   ./install.sh --global [--server NAME]
#   then, in each repo:  ./install.sh /path/to/repo --claude-md-only --test CMD --lint CMD --static CMD
#
#   --server          MCP server name as shown by /mcp (default: intrackr-developer)
#   --test/--lint/--static
#                     This repo's full test suite, lint and static-analysis commands.
#                     They go into CLAUDE.md, never into the skill, so the skill stays stack-agnostic.
#   --claude-md-only  Only append the CLAUDE.md pointer and commands (use after --global)
#   --global          Install skill, agents and hook into ~/.claude instead of a repo
#
# Nothing is deleted. The CLAUDE.md snippet is appended once. An existing settings.json is merged with jq.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
target=""; mode="repo"; server="intrackr-developer"; test_cmd=""; lint_cmd=""; static_cmd=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --global)         mode="global"; shift ;;
    --claude-md-only) mode="claude-md"; shift ;;
    --server)         server="$2"; shift 2 ;;
    --test)           test_cmd="$2"; shift 2 ;;
    --lint)           lint_cmd="$2"; shift 2 ;;
    --static)         static_cmd="$2"; shift 2 ;;
    -*)               echo "unknown option: $1" >&2; exit 1 ;;
    *)                target="$1"; shift ;;
  esac
done
command -v jq >/dev/null || { echo "jq is required (the done-blocking hook uses it)." >&2; exit 1; }

install_hook() { # install_hook SETTINGS_FILE
  local file="$1" hook_json
  hook_json="$(jq --arg m "mcp__${server}__update_task" '.hooks.PreToolUse[0].matcher = $m' "$here/.claude/settings.json")"
  mkdir -p "$(dirname "$file")"
  if [[ -f "$file" ]]; then
    jq -s '.[0] as $cur | .[1] as $new
      | $cur | .hooks.PreToolUse = ((($cur.hooks.PreToolUse // []) | map(select(.matcher != $new.hooks.PreToolUse[0].matcher))) + $new.hooks.PreToolUse)' \
      "$file" <(echo "$hook_json") > "$file.tmp" && mv "$file.tmp" "$file"
  else
    echo "$hook_json" > "$file"
  fi
}

install_skill_and_agents() { # install_skill_and_agents CLAUDE_DIR
  mkdir -p "$1/skills/intrackr-task" "$1/agents"
  cp "$here/.claude/skills/intrackr-task/SKILL.md" "$1/skills/intrackr-task/SKILL.md"
  cp "$here/.claude/agents/scout.md" "$here/.claude/agents/planner.md" "$here/.claude/agents/task-reviewer.md" "$1/agents/"
}

install_claude_md() { # run inside the repo
  local memory="CLAUDE.md"
  [[ ! -f CLAUDE.md && -f AGENTS.md ]] && memory="AGENTS.md"
  if ! grep -q 'intrackr-task' "$memory" 2>/dev/null; then
    snippet="$(cat "$here/CLAUDE.md.snippet")"
    [[ -n "$test_cmd" ]]   && snippet="${snippet//<TEST_COMMAND>/$test_cmd}"
    [[ -n "$lint_cmd" ]]   && snippet="${snippet//<LINT_COMMAND>/$lint_cmd}"
    [[ -n "$static_cmd" ]] && snippet="${snippet//<STATIC_ANALYSIS_COMMAND>/$static_cmd}"
    printf '%s\n' "$snippet" >> "$memory"
  fi
  grep -qx '.claude/task/' .gitignore 2>/dev/null || echo '.claude/task/' >> .gitignore
  echo "  $memory  (pointer and commands appended)"
  echo "  .gitignore  (.claude/task/)"
  if grep -q '<[A-Z_]*>' "$memory"; then
    echo; echo "Still to fill in $memory:"; grep -o '<[A-Z_]*>' "$memory" | sort -u | sed 's/^/  /'
  fi
}

case "$mode" in
  global)
    install_skill_and_agents "$HOME/.claude"
    install_hook "$HOME/.claude/settings.json"
    echo "Installed into ~/.claude (all repos on this machine)"
    echo "  ~/.claude/skills/intrackr-task/SKILL.md"
    echo "  ~/.claude/agents/{scout,planner,task-reviewer}.md"
    echo "  ~/.claude/settings.json  (hook matcher: mcp__${server}__update_task)"
    echo; echo "Now in each repo: $0 /path/to/repo --claude-md-only --test CMD --lint CMD --static CMD"
    ;;
  repo|claude-md)
    [[ -n "$target" && -d "$target" ]] || { echo "usage: $0 /path/to/repo [options]   or   $0 --global" >&2; exit 1; }
    cd "$target"
    echo "Installed into $target"
    if [[ "$mode" == repo ]]; then
      install_skill_and_agents ".claude"
      install_hook ".claude/settings.json"
      echo "  .claude/skills/intrackr-task/SKILL.md"
      echo "  .claude/agents/{scout,planner,task-reviewer}.md"
      echo "  .claude/settings.json  (hook matcher: mcp__${server}__update_task)"
    fi
    install_claude_md
    echo; echo "Next: run /context and /agents in a fresh Claude Code session, then commit."
    ;;
esac
