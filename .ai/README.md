# AI Workflow

This directory contains the repo-local AI pipeline for this project.

Goals:
- keep AI tooling out of the Godot runtime folders
- keep roles model-agnostic
- allow `codex` and `claude` to be swapped per run
- start small: planner, builder, reviewer
- run cheap local verification automatically before final review

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
- `tasks/` materialized task files that the orchestrator can hand to the pipeline

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
- `pipeline.ps1` runs the configured stages in one go, supports provider fallbacks per stage, and stops automatically on verify or reviewer failure when the pipeline config says so.
- `pipeline.ps1` prepares a scoped reviewer task from the requested context files and their diff, so review targets the feature change set instead of the whole dirty worktree.
- The default pipeline now includes a local `verify` stage for cheap headless Godot checks before review.
- Reviewer stages can declare `accepted_review_findings` patterns for known, explicitly tolerated findings; unmatched findings still fail the run.
- Successful pipeline runs keep the current run directory and prune older `.ai/runs/*` artifacts when `post_run.cleanup_run_artifacts` is enabled.
- Pipeline summaries now include the run directory, per-stage status, and changed files from the resulting diff.

Default pipeline shape:

```json
{
  "stages": [
    { "name": "planner", "role": "planner", "provider": "codex", "fallback_providers": ["claude"] },
    { "name": "builder", "role": "builder", "provider": "codex", "fallback_providers": ["claude"] },
    {
      "name": "verify",
      "role": "verify",
      "provider": "powershell",
      "commands": [
        { "name": "project-parse", "command": "godot --headless --quit --path ." }
      ]
    },
    {
      "name": "reviewer",
      "role": "reviewer",
      "provider": "codex",
      "fallback_providers": ["claude"],
      "accepted_review_findings": []
    }
  ]
}
```

Orchestrator expectations:
- for concrete implementation tasks, the orchestrator should be pipeline-first: use `.ai/pipeline.ps1` rather than editing repo files directly
- if the task only exists in chat, the orchestrator should first materialize it as a task file under `.ai/tasks/`, then start the pipeline
- before starting the pipeline, the orchestrator should briefly tell the user what it understood and how it plans to proceed
- the orchestrator should only bypass the normal pipeline for analysis-only requests or when repairing the pipeline itself
- during a normal feature run, the orchestrator should not create ad hoc `.ai/pipelines/*.json` files or other orchestration helpers just to get through one stage
- if the run reveals that the AI workflow should change, the orchestrator should finish the run first when possible, then suggest those `.ai/*` changes in the retrospective instead of editing workflow files mid-run

Recommended session prompt:

```text
Orchestrator-Modus für dieses Repo. Folge strikt `.ai/orchestrator.md`.

Für konkrete Umsetzungsaufgaben gilt:
- pipeline-first über `.ai/pipeline.ps1`
- keine direkten Repo-Edits durch den Orchestrator, solange die Pipeline lauffähig ist
- wenn die Aufgabe nur im Chat existiert, materialisiere sie zuerst als Datei unter `.ai/tasks/`
- erfinde keine ad-hoc `.ai/pipelines/*.json` oder andere Workflow-Helfer für diesen einen Durchlauf
- wenn dir Verbesserungen an der AI-Pipeline auffallen, schlage sie erst im Abschluss anstatt sie mitten im Feature-Run ungefragt einzubauen

Bevor du startest, sag mir kurz:
1. was du verstanden hast
2. wie du vorgehen willst

Nach dem Durchlauf:
1. Iterationen zusammenfassen
2. Learnings / sinnvolle `.ai/*`-Anpassungen nennen
3. sagen, was ich manuell testen soll
4. `.ai/runs/` zuerst aufräumen
5. Commit-Message vorschlagen
6. fragen, ob committed werden soll

Task: <deine Aufgabe>
```
