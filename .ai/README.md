# AI Workflow

This directory contains the repo-local AI pipeline for this project.

Goals:
- keep AI tooling out of the Godot runtime folders
- keep roles model-agnostic
- allow `codex` and `claude` to be swapped per run
- start small: planner, builder, reviewer

Current layout:
- `orchestrator.md` autonomy policy for the main assistant
- `pipelines/` machine-readable stage definitions
- `roles/` role definitions and operating rules
- `context/` repo-specific constraints layered on top of `CLAUDE.md`
- `schemas/` structured output contracts
- `providers/` thin wrappers around local AI CLIs
- `runs/` generated prompt/result artifacts for real executions
- `run.ps1` single-role entry point
- `pipeline.ps1` multi-stage entry point

Usage examples:

```powershell
powershell -ExecutionPolicy Bypass -File .ai/run.ps1 `
  -Role reviewer `
  -Provider codex `
  -Task "Review the current uncommitted changes for regressions." `
  -DryRun
```

```powershell
powershell -ExecutionPolicy Bypass -File .ai/run.ps1 `
  -Role builder `
  -Provider claude `
  -Task "Implement the requested inventory tooltip improvements." `
  -ContextFiles "scripts/inventory/inventory.gd","scenes/main/inventory_manager.gd"
```

```powershell
powershell -ExecutionPolicy Bypass -File .ai/run.ps1 `
  -Role planner `
  -Provider codex `
  -TaskFile ".ai/tasks/held-item-in-hand.md"
```

```powershell
powershell -ExecutionPolicy Bypass -File .ai/pipeline.ps1 `
  -TaskFile ".ai/tasks/held-item-in-hand.md"
```

Notes:
- `reviewer` defaults to the schema in `schemas/review-result.json`.
- `builder` and `planner` return normal text unless a schema is supplied explicitly.
- Provider-specific behavior is intentionally thin in `v1`; the role files remain the source of truth.
- Real runs snapshot `task.md`, `prompt.md`, and `result.txt` under `.ai/runs/<timestamp>-<role>-<provider>/`.
- `pipeline.ps1` runs the configured stages in one go and stops automatically on reviewer failure when the pipeline config says so.
- `pipeline.ps1` prepares a scoped reviewer task from the requested context files and their diff, so review targets the feature change set instead of the whole dirty worktree.
