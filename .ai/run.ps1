[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("planner", "builder", "reviewer")]
    [string]$Role,

    [Parameter(Mandatory = $true)]
    [ValidateSet("codex", "claude")]
    [string]$Provider,

    [string]$Task = "",

    [string[]]$ContextFiles = @(),
    [string]$TaskFile,
    [string]$SchemaPath,
    [string]$OutputPath,
    [switch]$DryRun
)

$OutputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$rolePath = Join-Path $PSScriptRoot ("roles/{0}.md" -f $Role)

if (-not (Test-Path -LiteralPath $rolePath)) {
    throw "Role file not found: $rolePath"
}

$normalizedContextFiles = @()
foreach ($entry in $ContextFiles) {
    if ([string]::IsNullOrWhiteSpace($entry)) {
        continue
    }

    foreach ($part in ($entry -split ",")) {
        $trimmed = $part.Trim()
        if (-not [string]::IsNullOrWhiteSpace($trimmed)) {
            $normalizedContextFiles += $trimmed
        }
    }
}

$resolvedContextFiles = @()
foreach ($file in $normalizedContextFiles) {
    $candidate = Join-Path $repoRoot $file
    if (Test-Path -LiteralPath $candidate) {
        $resolvedContextFiles += (Resolve-Path $candidate).Path
    } else {
        $resolvedContextFiles += $file
    }
}

if (-not $SchemaPath -and $Role -eq "reviewer") {
    $SchemaPath = Join-Path $PSScriptRoot "schemas/review-result.json"
}

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

if ([string]::IsNullOrWhiteSpace($Task) -and [string]::IsNullOrWhiteSpace($resolvedTaskFile)) {
    throw "Provide either -Task or -TaskFile."
}

$taskBody = if (-not [string]::IsNullOrWhiteSpace($resolvedTaskFile)) {
    Read-Utf8Text $resolvedTaskFile
} else {
    $Task
}

$rolePrompt = Read-Utf8Text $rolePath
$claudeRulesPath = Join-Path $repoRoot "CLAUDE.md"
$repoRulesPath = Join-Path $PSScriptRoot "context/repo_rules.md"

$claudeRulesBlock = if (Test-Path -LiteralPath $claudeRulesPath) {
    "--- BEGIN CLAUDE.md ($claudeRulesPath) ---`n" + (Read-Utf8Text $claudeRulesPath) + "`n--- END CLAUDE.md ---"
} else {
    "(CLAUDE.md not found)"
}

$repoRulesBlock = if (Test-Path -LiteralPath $repoRulesPath) {
    "--- BEGIN repo_rules.md ($repoRulesPath) ---`n" + (Read-Utf8Text $repoRulesPath) + "`n--- END repo_rules.md ---"
} else {
    "(repo_rules.md not found)"
}

$contextBlock = if ($resolvedContextFiles.Count -gt 0) {
    ($resolvedContextFiles | ForEach-Object { "- $_" }) -join "`n"
} else {
    "- none provided"
}

$schemaBlock = if ($SchemaPath) {
    "Return output that matches the schema at: $SchemaPath"
} else {
    "No output schema is enforced for this run."
}

$prompt = @"
You are running inside the repository at:
$repoRoot

Binding repo conventions (treat as authoritative; follow over any general habits):

$claudeRulesBlock

$repoRulesBlock

Role definition:
$rolePrompt

Task:
$taskBody

Preferred context files:
$contextBlock

Output contract:
$schemaBlock
"@

$runsRoot = Join-Path $PSScriptRoot "runs"
$runId = "{0}-{1}-{2}" -f ([DateTime]::UtcNow.ToString("yyyyMMdd-HHmmss")), $Role, $Provider
$runDir = Join-Path $runsRoot $runId
$promptPath = Join-Path $runDir "prompt.md"
$taskSnapshotPath = Join-Path $runDir "task.md"
$resolvedOutputPath = if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath
} else {
    Join-Path $runDir "result.txt"
}

$providerScript = Join-Path $PSScriptRoot ("providers/{0}.ps1" -f $Provider)
if (-not (Test-Path -LiteralPath $providerScript)) {
    throw "Provider script not found: $providerScript"
}

[System.IO.Directory]::CreateDirectory($runsRoot) | Out-Null
[System.IO.Directory]::CreateDirectory($runDir) | Out-Null
Write-Utf8Text -Path $taskSnapshotPath -Content $taskBody
Write-Utf8Text -Path $promptPath -Content $prompt

 & $providerScript `
     -PromptPath $promptPath `
     -RepoRoot $repoRoot `
     -SchemaPath $SchemaPath `
     -OutputPath $resolvedOutputPath `
     -RunDirectory $runDir `
     -AllowModelWrite:($Role -eq "builder") `
     -DryRun:$DryRun
