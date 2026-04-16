[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PromptPath,

    [Parameter(Mandatory = $true)]
    [string]$RepoRoot,

    [string]$SchemaPath,
    [string]$OutputPath,
    [string]$RunDirectory,
    [switch]$AllowModelWrite,
    [switch]$DryRun
)

$prompt = [System.IO.File]::ReadAllText($PromptPath, [System.Text.UTF8Encoding]::new($false))
$args = @("exec", "--cd", $RepoRoot)

if ($AllowModelWrite) {
    $args += "--dangerously-bypass-approvals-and-sandbox"
} else {
    $args += @("--sandbox", "workspace-write")
}

if ($SchemaPath) {
    $args += @("--output-schema", $SchemaPath)
}

if ($OutputPath) {
    $args += @("--output-last-message", $OutputPath)
}

$args += "-"

if ($DryRun) {
    [pscustomobject]@{
        provider = "codex"
        command = @("codex.cmd") + $args
        schema = $SchemaPath
        output_path = $OutputPath
        prompt_path = $PromptPath
        run_directory = $RunDirectory
        allow_model_write = [bool]$AllowModelWrite
        prompt_preview = $prompt.Substring(0, [Math]::Min(300, $prompt.Length))
    } | ConvertTo-Json -Depth 4
    return
}

$prompt | & codex.cmd @args
