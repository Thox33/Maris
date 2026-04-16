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

$args = @(
    "-p",
    "--permission-mode", "acceptEdits",
    "--add-dir", $RepoRoot
)

if ($SchemaPath) {
    $schema = [System.IO.File]::ReadAllText($SchemaPath, [System.Text.UTF8Encoding]::new($false))
    $args += @("--json-schema", $schema)
}

if ($OutputPath) {
    $args += @("--output-format", "text")
}

$prompt = [System.IO.File]::ReadAllText($PromptPath, [System.Text.UTF8Encoding]::new($false))

if ($DryRun) {
    [pscustomobject]@{
        provider = "claude"
        command = @("claude.cmd") + $args
        schema = $SchemaPath
        output_path = $OutputPath
        prompt_path = $PromptPath
        run_directory = $RunDirectory
        allow_model_write = [bool]$AllowModelWrite
        prompt_preview = $prompt.Substring(0, [Math]::Min(300, $prompt.Length))
    } | ConvertTo-Json -Depth 4
    return
}

$result = $prompt | & claude.cmd @args

if ($OutputPath) {
    [System.IO.File]::WriteAllText($OutputPath, $result, [System.Text.UTF8Encoding]::new($false))
}

$result
