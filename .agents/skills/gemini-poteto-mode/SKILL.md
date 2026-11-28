---
name: gemini-poteto-mode
description: >-
  Antigravity-native adapter for the pstack poteto-mode workflow in Sleeves.
  Use when the user invokes /gemini-poteto-mode, asks to run /poteto-mode or pstack
  in Antigravity, or requests poteto-style execution, arena, interrogate, or
  pstack swarm workflows.
---

# Antigravity Poteto Mode Adapter

Upstream pstack remains the single source of truth for principles, playbooks,
and reply style. This adapter binds pstack cleanly to Antigravity's native tools,
workspace isolation, model tiers, and Sleeves repository rules.

## 1. Bootstrap (every run)

1. Resolve the repository root dynamically with `git rev-parse --show-toplevel`
   (call it `<repo>`). Never hardcode user-specific absolute paths.
2. Read `<repo>/.agents/plugins/pstack/skills/poteto-mode/SKILL.md` in full.
   (It sets `disable-model-invocation: true`, so it is hidden from the skill
   catalog and must be loaded directly.)
3. Match the task to a playbook under
   `<repo>/.agents/plugins/pstack/skills/poteto-mode/playbooks/<kebab>.md`
   (or `../figure-it-out/SKILL.md` when no playbook fits) and load its phases
   into `update_steps`.
4. Read the leaf `principle-*.md` file in full before citing or applying any
   principle.

## 2. Mandatory Delegate Kickoff Contract

`poteto-agent` falls back to `~/.cursor/plugins/` when given no path, which
fails in this repo. Every spawned delegate prompt MUST begin with:

```text
Read <repo>/.agents/plugins/pstack/skills/poteto-mode/worker.md before anything else.
Poteto skill path: <repo>/.agents/plugins/pstack/skills/poteto-mode/SKILL.md
```

Follow immediately with the user goal, exact task, owned scope/files, and
verification bar. Pass file paths, not inlined file dumps.

## 3. Cursor-to-Antigravity Tool Mapping

| Upstream pstack | Antigravity native | Notes |
| :--- | :--- | :--- |
| `Task` (write / playbook delegate) | `invoke_subagent` (`TypeName: "poteto-agent"`) | Runs async automatically; do not poll. |
| `Task` (readonly review / judge / explore) | `invoke_subagent` (`TypeName: "research"`) | Enforces read-only sandbox at tool level. |
| `Task` (`no-comments` / quality audit / CI) | `invoke_subagent` (`comment-sicko`, `thermo-nuclear-code-quality-review`, `ci-watcher`) | Already loaded as Antigravity subagents. |
| Parallel writers (`arena`, `swarm`, `interrogate`) | `invoke_subagent` with `Workspace: "share"` (or `"branch"`) | Native isolated working copy; no manual `git worktree` boilerplate needed. |
| Large fan-out / staged pipeline | `run_workflow` (read `run-workflow` skill first) | Prefer over manual multi-turn orchestration when fanning out across many slices or aggregating programmatically. |
| Todolist tool | `update_steps` (+ `update_focus` for intra-step status) | Copy playbook phases into `update_steps` before starting work. |
| `AskQuestion` | `ask_question` | Only for irreversible choices or genuine ambiguity; never block on reversible work. |
| Fresh vs resume subagent | New `invoke_subagent` by default; `send_message` only when costly state (checkout, uncommitted work, live process) lives in the subagent | Matches upstream "Fresh subagents by default". |
| `/deslop`, `control-cli`, `control-ui`, `verify-this` | `<repo>/.agents/plugins/cursor-team-kit/skills/<name>/SKILL.md` | Installed in this repo. |
| `environment: "cloud"` / `cloud_base_branch` | Unsupported in `invoke_subagent` | Never fake cloud execution if the user explicitly requested remote cloud execution; otherwise run locally with `Workspace: "share"` or `"branch"`. |

**Critical guardrail (`swarm` naming collision):** Never invoke Antigravity's
built-in `swarm` tool to run pstack's `swarm` skill unless the user explicitly
invoked `/swarm`. Execute pstack's `swarm` skill via parallel `invoke_subagent`
calls or `run_workflow`.

## 4. Model Tiering & Honest Diversity Rules

Antigravity does not load `~/.cursor/rules/pstack-models.mdc` and
`invoke_subagent` accepts only `Model: "inherit" | "pro" | "flash" | "flash_lite"`
(never Cursor model slugs).

- **High-judgment / code / design / `arena` candidates / `interrogate` adversaries**:
  `Model: "inherit"` (or `"pro"` when escalating subtle work from a lighter parent).
- **Mechanical fan-out / routine verification / high-volume `swarm` slices**:
  `Model: "flash"` (or `"flash_lite"` for trivial extraction).
- **No silent fake multi-vendor panels**: `invoke_subagent` cannot pick a
  different vendor's model for `arena` Phase C (Cross-judge) or `interrogate`
  panels. State this explicitly in the synthesis report (e.g., "single-vendor
  fresh-context judge; cross-vendor isolation unavailable via `invoke_subagent`").
  Compensate structurally:
  - In `arena`: run the judge as a fresh `research` subagent seeing only the
    rubric and candidate artifact paths (never the parent's rationale).
  - In `interrogate`: assign each adversary a distinct failure lens (e.g.
    concurrency/state, persistence/boundaries, UI/event lifecycle) in its own
    `Workspace: "share"` copy.
  - Only when the user explicitly invokes `/swarm` may you check
    `swarm(action: "models")` for real cross-vendor seats.

## 5. Sleeves Repository Overrides (`AGENTS.md` Precedence)

When upstream pstack conflicts with `<repo>/AGENTS.md`, `AGENTS.md` wins for
Sleeves application code:

1. **Review gate (`builder-reviewer-loop`) vs `worker.md`**:
   `worker.md` forbids adding unstated gates, while `AGENTS.md` Rule 5 requires
   a read-only review gate before completing code changes. Resolve this cleanly
   by including the review gate **in the stated bar from step 1** for any
   Swift/project code change (use `TypeName: "research"` as the read-only
   reviewer). Pure docs or skill edits do not require Xcode builds or app
   relaunch.
2. **Native macOS verification (`prove-it-works`)**:
   Do not rely on browser-oriented `control-ui` for native SwiftUI/AppKit
   behavior. Prove changes with:
   - `os.Logger` (`subsystem: "com.cacheandbuffer.Sleeves"`, `privacy: .public`)
   - `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodegen generate`
     whenever Swift files are added, removed, or renamed
   - `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Sleeves.xcodeproj -scheme Sleeves -configuration Debug -derivedDataPath .build build`
   - `/usr/bin/log show --last 5m --style compact --info --predicate 'subsystem == "com.cacheandbuffer.Sleeves"'`
   - `--catalog-test`, `screencapture`, or CGEvent synthesis when runtime UI
     evidence is needed
3. **Always relaunch after code changes (`AGENTS.md` Rule 6)**:
   Finish every code-change task with `pkill -x Sleeves; open .build/Build/Products/Debug/Sleeves.app`
   so the user never inspects a stale binary.
