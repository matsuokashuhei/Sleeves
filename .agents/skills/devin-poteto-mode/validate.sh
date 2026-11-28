#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"

fail() {
  printf 'validate.sh: %s\n' "$*" >&2
  exit 1
}

require_file() {
  [[ -f "$1" ]] || fail "missing $1"
}

count_matches() {
  local pattern="$1"
  local file="$2"
  rg -c "$pattern" "$file" 2>/dev/null || printf '0'
}

command -v jq >/dev/null 2>&1 || fail "jq is not installed"
command -v rg >/dev/null 2>&1 || fail "rg is not installed"

if ! jq -e '.requiredPlugins? // [] | index("./.agents/plugins/pstack") != null' .devin/config.json >/dev/null 2>&1; then
  fail '.devin/config.json does not require ./.agents/plugins/pstack'
fi

require_file ".agents/plugins/pstack/skills/poteto-mode/SKILL.md"
require_file ".agents/plugins/pstack/skills/poteto-mode/worker.md"
require_file ".agents/skills/devin-poteto-mode/SKILL.md"
require_file ".devin/agents/poteto-swe-write.md"
require_file ".devin/agents/poteto-swe-review.md"

require_fixed() {
  local needle="$1"
  local file="$2"
  rg -q -F -- "$needle" "$file" 2>/dev/null || fail "$file missing required text: $needle"
}

adapter=".agents/skills/devin-poteto-mode/SKILL.md"
write_profile=".devin/agents/poteto-swe-write.md"
review_profile=".devin/agents/poteto-swe-review.md"

require_fixed '.agents/plugins/pstack/skills/poteto-mode/SKILL.md' "$adapter"
require_fixed 'Read <repo>/.agents/plugins/pstack/skills/poteto-mode/worker.md before anything else.' "$adapter"
require_fixed 'git rev-parse --show-toplevel' "$adapter"
if rg -q '/Users/' "$adapter" 2>/dev/null; then
  fail "$adapter must not contain a developer-specific /Users path"
fi
require_fixed '`Task` -> `run_subagent`' "$adapter"
require_fixed '`subagent_type` -> `profile`' "$adapter"
require_fixed '`run_in_background` -> `is_background`' "$adapter"
require_fixed '`generalPurpose`/`inherit-parent`/`auto` -> `subagent_general`' "$adapter"
require_fixed '`/deslop` -> `/cursor-team-kit:deslop`' "$adapter"
require_fixed '`control-ui` -> `/cursor-team-kit:control-ui`' "$adapter"
require_fixed '`control-cli` -> `/cursor-team-kit:control-cli`' "$adapter"
require_fixed 'os.Logger' "$adapter"
require_fixed 'screencapture' "$adapter"
require_fixed 'Unknown subagent profile' "$adapter"
require_fixed 'cloud_base_branch' "$adapter"
require_fixed 'auto-deny unapproved write and execution tools' "$adapter"
require_fixed 'use foreground execution by default' "$adapter"
require_fixed 'does not create Devin Cloud sessions' "$adapter"
require_fixed 'separate git worktree' "$adapter"
require_fixed 'serialize the workers' "$adapter"

shopt -s nullglob
poteto_profiles=(.devin/agents/poteto-*.md)
(( ${#poteto_profiles[@]} == 2 )) || fail "expected exactly two .devin/agents/poteto-*.md files, found ${#poteto_profiles[@]}"

if rg -q '^allowed-tools:' "$write_profile" 2>/dev/null; then
  fail "$write_profile should not restrict allowed-tools"
fi
actual_tools="$(awk '
  /^allowed-tools:/ { in_block=1; print; next }
  in_block && /^  - / { print; next }
  in_block { exit }
' "$review_profile")"
expected_tools='allowed-tools:
  - read
  - grep
  - glob
  - exec'
[[ "$actual_tools" == "$expected_tools" ]] || fail "$review_profile must restrict allowed-tools exactly to read, grep, glob, and exec"
require_fixed 'Do not edit, create, delete, move, or otherwise mutate files.' "$review_profile"
require_fixed 'Review evidence, not self-reports.' "$review_profile"

for profile in "$write_profile" "$review_profile"; do
  model_lines="$(count_matches '^model:' "$profile")"
  exact_model_lines="$(count_matches '^model: swe-2-1-high$' "$profile")"
  [[ "$model_lines" == "1" && "$exact_model_lines" == "1" ]] || fail "$profile must contain exactly one line: model: swe-2-1-high"
done

if ! skills_output="$(devin skills list 2>&1)"; then
  fail "devin skills list failed: $skills_output"
fi

rg -q -F '/pstack:poteto-mode' <<< "$skills_output" || fail "devin skills list does not contain /pstack:poteto-mode"
rg -q -F '/devin-poteto-mode' <<< "$skills_output" || fail "devin skills list does not contain /devin-poteto-mode"

printf 'validate.sh: ok\n'
