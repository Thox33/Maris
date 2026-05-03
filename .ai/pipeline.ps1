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
        [string]$RepoRoot,
        [string[]]$SupplementalSections = @()
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

    $sections = @(
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
    )

    foreach ($section in $SupplementalSections) {
        if ([string]::IsNullOrWhiteSpace($section)) {
            continue
        }
        $sections += ""
        $sections += $section
    }

    return ($sections -join "`n")
}

function Get-StageProviders {
    param($Stage)

    $providers = @()
    if ($Stage.PSObject.Properties.Name -contains "provider" -and -not [string]::IsNullOrWhiteSpace([string]$Stage.provider)) {
        $providers += [string]$Stage.provider
    }

    if ($Stage.PSObject.Properties.Name -contains "fallback_providers") {
        foreach ($provider in @($Stage.fallback_providers)) {
            $providerName = [string]$provider
            if ([string]::IsNullOrWhiteSpace($providerName) -or $providerName -in $providers) {
                continue
            }
            $providers += $providerName
        }
    }

    return $providers
}

function Split-ReviewFindings {
    param(
        $ReviewJson,
        $AcceptedRules
    )

    $accepted = @()
    $unaccepted = @()
    $rules = @($AcceptedRules)

    foreach ($finding in @($ReviewJson.findings)) {
        $isAccepted = $false
        foreach ($rule in $rules) {
            if ($null -eq $rule) {
                continue
            }

            $severityMatches = $true
            if ($rule.PSObject.Properties.Name -contains "severity" -and -not [string]::IsNullOrWhiteSpace([string]$rule.severity)) {
                $severityMatches = ([string]$finding.severity) -eq ([string]$rule.severity)
            }

            $fileMatches = $true
            if ($rule.PSObject.Properties.Name -contains "file_contains" -and -not [string]::IsNullOrWhiteSpace([string]$rule.file_contains)) {
                $fileMatches = ([string]$finding.file).Contains([string]$rule.file_contains)
            }

            $issueMatches = $true
            if ($rule.PSObject.Properties.Name -contains "issue_contains" -and -not [string]::IsNullOrWhiteSpace([string]$rule.issue_contains)) {
                $issueMatches = ([string]$finding.issue).Contains([string]$rule.issue_contains)
            }

            if ($severityMatches -and $fileMatches -and $issueMatches) {
                $isAccepted = $true
                break
            }
        }

        if ($isAccepted) {
            $accepted += $finding
        } else {
            $unaccepted += $finding
        }
    }

    return @{
        accepted = @($accepted)
        unaccepted = @($unaccepted)
    }
}

function Invoke-VerifyStage {
    param(
        $Stage,
        [string]$RepoRoot,
        [string]$OutputPath,
        [switch]$DryRun
    )

    $results = @()
    foreach ($commandConfig in @($Stage.commands)) {
        $commandName = [string]$commandConfig.name
        $commandText = [string]$commandConfig.command
        if ([string]::IsNullOrWhiteSpace($commandText)) {
            continue
        }

        if ([string]::IsNullOrWhiteSpace($commandName)) {
            $commandName = $commandText
        }

        $entry = [ordered]@{
            name = $commandName
            command = $commandText
            status = if ($DryRun) { "dry_run" } else { "passed" }
            exit_code = 0
            output = ""
        }

        if (-not $DryRun) {
            Push-Location $RepoRoot
            try {
                $output = & powershell -ExecutionPolicy Bypass -Command $commandText 2>&1 | Out-String
                $exitCode = if ($null -ne $LASTEXITCODE) { [int]$LASTEXITCODE } else { 0 }
                $entry.output = $output.TrimEnd()
                $entry.exit_code = $exitCode
                if ($exitCode -ne 0) {
                    $entry.status = "failed"
                }
            } finally {
                Pop-Location
            }
        }

        $results += $entry
        if ($entry.status -eq "failed") {
            break
        }
    }

    $status = "pass"
    if (@($results | Where-Object { $_.status -eq "failed" }).Count -gt 0) {
        $status = "fail"
    } elseif ($DryRun) {
        $status = "dry_run"
    }

    $payload = [ordered]@{
        status = $status
        commands = $results
    }
    Write-Utf8Text -Path $OutputPath -Content (($payload | ConvertTo-Json -Depth 8))
    return $payload
}

function Cleanup-PreviousRunArtifacts {
    param(
        [string]$RunsRoot,
        [string]$KeepPath
    )

    foreach ($entry in Get-ChildItem -LiteralPath $RunsRoot -Force) {
        if ($entry.Name -eq ".gitkeep") {
            continue
        }
        if ($entry.FullName -eq $KeepPath) {
            continue
        }
        Remove-Item -LiteralPath $entry.FullName -Recurse -Force
    }
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
    run_directory = $pipelineRunDir
    stages = @()
    final_status = "running"
}

$verifySectionsForReviewer = @()
foreach ($stage in $enabledStages) {
    $stageName = [string]$stage.name
    $role = [string]$stage.role
    $stageOutputPath = Join-Path $pipelineRunDir ("{0}.txt" -f $stageName)

    $stageResult = [ordered]@{
        name = $stageName
        role = $role
        output_path = $stageOutputPath
        status = "completed"
    }

    if ($role -eq "verify") {
        $stageResult["provider"] = "powershell"
        $verifyResult = Invoke-VerifyStage `
            -Stage $stage `
            -RepoRoot $repoRoot `
            -OutputPath $stageOutputPath `
            -DryRun:$DryRun
        $stageResult["verify_status"] = [string]$verifyResult.status
        $stageResult["commands"] = @($verifyResult.commands)
        $summary.stages += $stageResult

        $verifySectionsForReviewer += (
            @(
                "## Verification results"
                ""
                '```json'
                (Read-Utf8Text $stageOutputPath)
                '```'
            ) -join "`n"
        )

        if ([string]$verifyResult.status -eq "fail") {
            $summary.final_status = "failed_verify"
            $summary.verify_output_path = $stageOutputPath
            $summaryPath = Join-Path $pipelineRunDir "summary.json"
            Write-Utf8Text -Path $summaryPath -Content (($summary | ConvertTo-Json -Depth 8))
            Get-Content -Raw -LiteralPath $stageOutputPath
            return
        }

        continue
    }

    $stageProviders = Get-StageProviders -Stage $stage
    if ($stageProviders.Count -eq 0) {
        throw "Stage '$stageName' has no provider or fallback_providers configured."
    }

    $stageOutputWritten = $false
    $stageErrors = @()
    foreach ($provider in $stageProviders) {
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
                -RepoRoot $repoRoot `
                -SupplementalSections $verifySectionsForReviewer
            Write-Utf8Text -Path $scopedReviewerTaskPath -Content $scopedReviewerTask
            $invokeParams["TaskFile"] = $scopedReviewerTaskPath
        } elseif (-not [string]::IsNullOrWhiteSpace($resolvedTaskFile)) {
            $invokeParams["TaskFile"] = $resolvedTaskFile
        } else {
            $invokeParams["Task"] = $taskBody
        }

        try {
            & $runScript @invokeParams | Out-Null
            $stageResult["provider"] = $provider
            $stageOutputWritten = $true
            break
        } catch {
            $stageErrors += [ordered]@{
                provider = $provider
                error = $_.Exception.Message
            }
        }
    }

    if (-not $stageOutputWritten) {
        $stageResult["status"] = "failed"
        $stageResult["provider_attempts"] = $stageErrors
        $summary.stages += $stageResult
        $summary.final_status = "failed_stage"
        $summary.failed_stage = $stageName
        $summary.failed_stage_errors = $stageErrors
        $summaryPath = Join-Path $pipelineRunDir "summary.json"
        Write-Utf8Text -Path $summaryPath -Content (($summary | ConvertTo-Json -Depth 8))
        throw "Stage '$stageName' failed for all configured providers."
    }

    if ($role -eq "reviewer" -and -not $DryRun -and (Test-Path -LiteralPath $stageOutputPath)) {
        try {
            $reviewJson = Get-Content -Raw -LiteralPath $stageOutputPath | ConvertFrom-Json
            $stageResult["review_status"] = [string]$reviewJson.status
            $acceptedRules = @()
            if ($stage.PSObject.Properties.Name -contains "accepted_review_findings") {
                $acceptedRules = @($stage.accepted_review_findings)
            }
            $findingSplit = Split-ReviewFindings -ReviewJson $reviewJson -AcceptedRules $acceptedRules
            $acceptedFindings = @($findingSplit.accepted)
            $unacceptedFindings = @($findingSplit.unaccepted)
            if ($acceptedFindings.Count -gt 0) {
                $stageResult["accepted_findings_count"] = $acceptedFindings.Count
            }
            if ($pipeline.autonomy.stop_on_reviewer_fail -eq $true -and [string]$reviewJson.status -eq "fail") {
                if ($unacceptedFindings.Count -eq 0 -and $acceptedFindings.Count -gt 0) {
                    $stageResult["review_status"] = "accepted_with_findings"
                    $stageResult["raw_review_status"] = [string]$reviewJson.status
                    $summary.accepted_review_findings = @($acceptedFindings)
                } else {
                $summary.stages += $stageResult
                $summary.final_status = "failed_review"
                $summary.review_output_path = $stageOutputPath
                $summary.accepted_review_findings = @($acceptedFindings)
                $summary.unaccepted_review_findings = @($unacceptedFindings)
                $summaryPath = Join-Path $pipelineRunDir "summary.json"
                Write-Utf8Text -Path $summaryPath -Content (($summary | ConvertTo-Json -Depth 8))
                Get-Content -Raw -LiteralPath $stageOutputPath
                return
                }
            }
        } catch {
            $stageResult["review_status"] = "unparsed"
        }
    }

    $summary.stages += $stageResult
}

$summary.final_status = "passed"
$summary.changed_files = @((& git -C $repoRoot diff --name-only --relative 2>$null | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }))
$summaryPath = Join-Path $pipelineRunDir "summary.json"
Write-Utf8Text -Path $summaryPath -Content (($summary | ConvertTo-Json -Depth 8))
if (-not $DryRun -and $pipeline.post_run.cleanup_run_artifacts -eq $true) {
    Cleanup-PreviousRunArtifacts -RunsRoot $runsRoot -KeepPath $pipelineRunDir
}
Write-Output (($summary | ConvertTo-Json -Depth 8))
