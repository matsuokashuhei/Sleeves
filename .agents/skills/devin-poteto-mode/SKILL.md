---
name: devin-poteto-mode
description: Devin-specific adapter for pstack poteto-mode in Sleeves with fixed SWE 2.1 High subagent profiles. Use when the user invokes /devin-poteto-mode or asks for poteto mode in Devin.
triggers:
  - user
---

# devin-poteto-mode adapter

Resolve the repository checkout root before reading or spawning anything, for example with `git rev-parse --show-toplevel`. Let `<repo>` be that absolute path. Read `<repo>/.agents/plugins/pstack/skills/poteto-mode/SKILL.md` in full and follow it, except where this adapter overrides Cursor-specific behavior for Devin. This file is not a copy of pstack. The upstream pstack skill remains the source of truth for principles, playbooks, and working style.

## Absolute worker path rule

Every spawned agent prompt must start with exactly this line after substituting the resolved absolute `<repo>`:

`Read <repo>/.agents/plugins/pstack/skills/poteto-mode/worker.md before anything else.`

Do not hardcode a developer-specific absolute path in the prompt or this file. After that first line, include the goal, the task, and the absolute pstack poteto-mode skill path for every poteto delegate.

## Cursor-to-Devin mapping

- `Task` -> `run_subagent`
- `subagent_type` -> `profile`
- `run_in_background` -> `is_background`
- `generalPurpose`/`inherit-parent`/`auto` -> `subagent_general`
- `/deslop` -> `/cursor-team-kit:deslop`
- `control-ui` -> `/cursor-team-kit:control-ui`
- `control-cli` -> `/cursor-team-kit:control-cli`

## Delegate profile mapping

Use the project custom subagent profiles in `.devin/agents/`:

- Implementation, prose, judgment, mechanical, swarm, arena, and interrogate write-capable delegates -> `poteto-swe-write`
- Review and verification delegates -> `poteto-swe-review`
- Any upstream instruction to use `poteto-agent` -> use the role-mapped project profile instead, normally `poteto-swe-write`

For poteto delegates, the role-mapped project profiles override the `generalPurpose`/`inherit-parent`/`auto` mapping. Use `subagent_general` only for work that is not a poteto delegate or when a project skill explicitly requires it.

Respect any narrower profile explicitly required by a project skill, such as `builder-reviewer-loop`. Do not create or use opus, codex, or gemini profiles for poteto delegates in this repository. When pstack names a Cursor model slug, treat the model choice as fixed by the custom profile instead.

## Profile availability

If `run_subagent` reports `Unknown subagent profile`, treat it as a stale profile list in the running session, not as missing configuration. Do not silently fall back to an unpinned profile. Report that a new Devin session is required to use the project profiles. `devin doctor` proves that Devin can load the profile files. It does not prove that the current session can spawn them.

## Background and permission behavior

`run_in_background` maps to `is_background`, but Devin background subagents auto-deny unapproved write and execution tools. For write-capable poteto delegates, use foreground execution by default in normal permission mode. Use background write delegates only when the user or session has already approved the required writes or explicitly accepts unattended operation. Read-only review and exploration delegates can run in the background. If a background delegate is denied, do not silently fall back to another profile. Respawn or resume it in the foreground with the original brief, every later directive, the prior report, and the branch or worktree.

## Cloud-only Cursor arguments and write isolation

Devin `run_subagent` has no `environment` or `cloud_base_branch` argument and does not create Devin Cloud sessions. Do not pass them. If the user explicitly requires cloud execution, say that this adapter cannot provide it through `run_subagent` instead of silently substituting local execution. Otherwise run poteto swarm workers locally.

Parallel write workers must not share mutable state. Give each worker a separate git worktree, or assign disjoint owned files and non-overlapping outputs. If neither isolation nor disjoint ownership is possible, serialize the workers. The parent integrates the results. If a worker needs a non-default base branch, the parent must prepare the branch or worktree, or name the exact branch or SHA in the worker task.

## Sleeves verification override

For Sleeves native macOS UI verification, use the repository's AGENTS.md methods: `os.Logger` instrumentation, `log show` or `log stream`, `screencapture`, CGEvent input synthesis, and Xcode MCP when available. Browser-only `control-ui` evidence is not sufficient proof for native macOS UI behavior.
