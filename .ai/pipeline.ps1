[CmdletBinding()]
param(
    [string]$Task = "",
    [string]$TaskFile,
    [string[]]$ContextFiles = @(),
    [string]$PipelineFile = ".ai/pipelines/default.json",
    [switch]$DryRun
)

$OutputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

function Read-Utf8Text {
    param([string]$Path)
    return [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false))
}

function Write-Utf8Text {
    param(
        [string]$Path,
        [string]$Content
    )
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

function Normalize-ContextFiles {
    param(
        [string[]]$Entries,
        [string]$RepoRoot
    )

    $normalized = @()
    foreach ($entry in $Entries) {
        if ([string]::IsNullOrWhiteSpace($entry)) {
            continue
        }

        foreach ($part in ($entry -split ",")) {
            $trimmed = $part.Trim()
            if ([string]::IsNullOrWhiteSpace($trimmed)) {
                continue
            }

            $candidate = Join-Path $RepoRoot $trimmed
            if (Test-Path -LiteralPath $candidate) {
                $normalized += (Resolve-Path $candidate).Path
            } elseif (Test-Path -LiteralPath $trimmed) {
                $normalized += (Resolve-Path $trimmed).Path
            } else {
                $normalized += $trimmed
            }
        }
    }

    return $normalized
}

function Get-RelativeScopeFiles {
    param(
        [string[]]$ScopeFiles,
        [string]$RepoRoot
    )

    $relativeFiles = @()
    foreach ($file in $ScopeFiles) {
        if ([string]::IsNullOrWhiteSpace($file)) {
            continue
        }

        $candidate = $file
        if (Test-Path -LiteralPath $candidate) {
            $resolved = (Resolve-Path $candidate).Path
            $repoPrefix = ((Resolve-Path $RepoRoot).Path.TrimEnd('\', '/')) + '\'
            if ($resolved.StartsWith($repoPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                $relativeFiles += $resolved.Substring($repoPrefix.Length)
            } else {
                $relativeFiles += $resolved
            }
        } else {
            $relativeFiles += $candidate
        }
    }

    return $relativeFiles
}

function Build-ScopedReviewerTask {
    param(
        [string]$BaseTaskBody,
        [string[]]$ScopeFiles,
        [string]$RepoRoot
    )

    $relativeScopeFiles = Get-RelativeScopeFiles -ScopeFiles $ScopeFiles -RepoRoot $RepoRoot
    $scopeBlock = if ($relativeScopeFiles.Count -gt 0) {
        ($relativeScopeFiles | ForEach-Object { '- `' + $_ + '`' }) -join "`n"
    } else {
        "- none provided"
    }

    $scopedDiff = ""
    if ($relativeScopeFiles.Count -gt 0) {
        $scopedDiff = (& git -C $RepoRoot diff --no-ext-diff -- @relativeScopeFiles 2>$null | Out-String).TrimEnd()
    }

    if ([string]::IsNullOrWhiteSpace($scopedDiff)) {
        $scopedDiff = "(no scoped diff available)"
    }

    return (
        @(
            $BaseTaskBody
            ""
            "## Scoped review target"
            ""
            "Primary files for this review:"
            $scopeBlock
            ""
            "Scope rules:"
            "- treat the files above and the scoped diff below as the primary review target"
            "- you may inspect additional files if needed for impact analysis, call-site verification, or neighboring logic"
            "- do not expand findings into unrelated dirty-worktree changes outside this scoped change set"
            ""
            "## Scoped diff"
            ""
            '```diff'
            $scopedDiff
            '```'
        ) -join "`n"
    )
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$runScript = Join-Path $PSScriptRoot "run.ps1"
$resolvedPipelineFile = Join-Path $repoRoot $PipelineFile
if (-not (Test-Path -LiteralPath $resolvedPipelineFile)) {
    if (Test-Path -LiteralPath $PipelineFile) {
        $resolvedPipelineFile = Resolve-Path $PipelineFile
    } else {
        throw "Pipeline file not found: $PipelineFile"
    }
}

if ([string]::IsNullOrWhiteSpace($Task) -and [string]::IsNullOrWhiteSpace($TaskFile)) {
    throw "Provide either -Task or -TaskFile."
}

$resolvedTaskFile = ""
if (-not [string]::IsNullOrWhiteSpace($TaskFile)) {
    $candidateTaskFile = Join-Path $repoRoot $TaskFile
    if (Test-Path -LiteralPath $candidateTaskFile) {
        $resolvedTaskFile = (Resolve-Path $candidateTaskFile).Path
    } elseif (Test-Path -LiteralPath $TaskFile) {
        $resolvedTaskFile = (Resolve-Path $TaskFile).Path
    } else {
        throw "Task file not found: $TaskFile"
    }
}

$taskBody = if (-not [string]::IsNullOrWhiteSpace($resolvedTaskFile)) {
    Read-Utf8Text $resolvedTaskFile
} else {
    $Task
}

$normalizedContextFiles = Normalize-ContextFiles -Entries $ContextFiles -RepoRoot $repoRoot

$pipeline = Get-Content -Raw -LiteralPath $resolvedPipelineFile | ConvertFrom-Json
$enabledStages = @($pipeline.stages | Where-Object { $_.enabled -eq $true })
if ($enabledStages.Count -eq 0) {
    throw "Pipeline has no enabled stages: $resolvedPipelineFile"
}

$runsRoot = Join-Path $PSScriptRoot "runs"
$pipelineRunId = "{0}-pipeline-{1}" -f ([DateTime]::UtcNow.ToString("yyyyMMdd-HHmmss")), $pipeline.name
$pipelineRunDir = Join-Path $runsRoot $pipelineRunId
[System.IO.Directory]::CreateDirectory($pipelineRunDir) | Out-Null

$summary = [ordered]@{
    pipeline = $pipeline.name
    pipeline_file = (Resolve-Path $resolvedPipelineFile).Path
    task = $Task
    task_file = $TaskFile
    stages = @()
    final_status = "running"
}

foreach ($stage in $enabledStages) {
    $stageName = [string]$stage.name
    $role = [string]$stage.role
    $provider = [string]$stage.provider
    $stageOutputPath = Join-Path $pipelineRunDir ("{0}.txt" -f $stageName)

    $invokeParams = @{
        Role = $role
        Provider = $provider
        ContextFiles = $normalizedContextFiles
        OutputPath = $stageOutputPath
        DryRun = $DryRun
    }

    if ($role -eq "reviewer") {
        $scopedReviewerTaskPath = Join-Path $pipelineRunDir ("{0}-task.md" -f $stageName)
        $scopedReviewerTask = Build-ScopedReviewerTask `
            -BaseTaskBody $taskBody `
            -ScopeFiles $normalizedContextFiles `
            -RepoRoot $repoRoot
        Write-Utf8Text -Path $scopedReviewerTaskPath -Content $scopedReviewerTask
        $invokeParams["TaskFile"] = $scopedReviewerTaskPath
    } elseif (-not [string]::IsNullOrWhiteSpace($resolvedTaskFile)) {
        $invokeParams["TaskFile"] = $resolvedTaskFile
    } else {
        $invokeParams["Task"] = $taskBody
    }

    & $runScript @invokeParams | Out-Null

    $stageResult = [ordered]@{
        name = $stageName
        role = $role
        provider = $provider
        output_path = $stageOutputPath
        status = "completed"
    }

    if ($role -eq "reviewer" -and -not $DryRun -and (Test-Path -LiteralPath $stageOutputPath)) {
        try {
            $reviewJson = Get-Content -Raw -LiteralPath $stageOutputPath | ConvertFrom-Json
            $stageResult["review_status"] = [string]$reviewJson.status
            if ($pipeline.autonomy.stop_on_reviewer_fail -eq $true -and [string]$reviewJson.status -eq "fail") {
                $summary.stages += $stageResult
                $summary.final_status = "failed_review"
                $summary.review_output_path = $stageOutputPath
                $summaryPath = Join-Path $pipelineRunDir "summary.json"
                Write-Utf8Text -Path $summaryPath -Content (($summary | ConvertTo-Json -Depth 6))
                Get-Content -Raw -LiteralPath $stageOutputPath
                return
            }
        } catch {
            $stageResult["review_status"] = "unparsed"
        }
    }

    $summary.stages += $stageResult
}

$summary.final_status = "passed"
$summaryPath = Join-Path $pipelineRunDir "summary.json"
Write-Utf8Text -Path $summaryPath -Content (($summary | ConvertTo-Json -Depth 6))
Write-Output (($summary | ConvertTo-Json -Depth 6))
