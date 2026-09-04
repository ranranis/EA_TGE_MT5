[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)] [string]$SourceFile,
    [Parameter(Mandatory=$true)] [string]$MetaEditorPath,
    [string]$LogPath
)

$ErrorActionPreference = 'Stop'
$runner = Join-Path $PSScriptRoot '..\.codex\skills\mql5-compile-reviewer\scripts\compile-mq5.ps1'
if(!(Test-Path -LiteralPath $runner -PathType Leaf)) {
    throw "Project compile reviewer is missing: $runner"
}

$arguments = @{
    SourceFile = $SourceFile
    MetaEditorPath = $MetaEditorPath
}
if(![string]::IsNullOrWhiteSpace($LogPath)) {
    $arguments.LogPath = $LogPath
}

& $runner @arguments
exit $LASTEXITCODE
