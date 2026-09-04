[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)] [string]$SourceFile,
    [string]$MetaEditorPath,
    [string]$LogPath
)

$ErrorActionPreference = 'Stop'

function Find-MetaEditor {
    $candidates = @(
        'C:\Program Files\MetaTrader 5\MetaEditor64.exe',
        'C:\Program Files\MetaTrader 5\metaeditor64.exe',
        'C:\Program Files (x86)\MetaTrader 5\MetaEditor64.exe',
        'C:\Program Files (x86)\MetaTrader 5\metaeditor64.exe'
    )
    foreach($candidate in $candidates) {
        if(Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    $terminalRoots = @($env:APPDATA, $env:LOCALAPPDATA) | Where-Object { $_ }
    foreach($root in $terminalRoots) {
        $base = Join-Path $root 'MetaQuotes\Terminal'
        if(!(Test-Path -LiteralPath $base)) { continue }
        $found = Get-ChildItem -LiteralPath $base -Filter 'metaeditor64.exe' -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if($found) { return $found.FullName }
    }
    return $null
}

function Find-ProjectRoot {
    param([Parameter(Mandatory=$true)][string]$StartDirectory)
    $current = [IO.DirectoryInfo](Resolve-Path -LiteralPath $StartDirectory).Path
    while($current) {
        if(Test-Path -LiteralPath (Join-Path $current.FullName 'AGENTS.md') -PathType Leaf) {
            return $current.FullName
        }
        $current = $current.Parent
    }
    return (Resolve-Path -LiteralPath $StartDirectory).Path
}

function Get-UniqueLogPath {
    param(
        [Parameter(Mandatory=$true)][string]$Directory,
        [Parameter(Mandatory=$true)][string]$FileName
    )
    $candidate = Join-Path $Directory $FileName
    if(!(Test-Path -LiteralPath $candidate)) { return $candidate }
    $extension = [IO.Path]::GetExtension($FileName)
    $baseName = [IO.Path]::GetFileNameWithoutExtension($FileName)
    for($index = 1; $index -lt 10000; $index++) {
        $candidate = Join-Path $Directory ("{0}_{1}{2}" -f $baseName, $index, $extension)
        if(!(Test-Path -LiteralPath $candidate)) { return $candidate }
    }
    throw "Could not allocate a unique compile log path for $FileName"
}

try {
    $source = (Resolve-Path -LiteralPath $SourceFile -ErrorAction Stop).Path
    $extension = [IO.Path]::GetExtension($source).ToLowerInvariant()
    if($extension -notin @('.mq5', '.mqh')) { throw "SourceFile must be .mq5 or .mqh: $source" }

    if([string]::IsNullOrWhiteSpace($MetaEditorPath)) { $MetaEditorPath = Find-MetaEditor }
    if([string]::IsNullOrWhiteSpace($MetaEditorPath) -or !(Test-Path -LiteralPath $MetaEditorPath -PathType Leaf)) {
        throw 'MetaEditor64.exe was not found. MetaEditor compilation was not performed.'
    }
    $MetaEditorPath = (Resolve-Path -LiteralPath $MetaEditorPath).Path
    $customLogPath = ![string]::IsNullOrWhiteSpace($LogPath)
    if(!$customLogPath) {
        $sourceDirectory = [IO.Path]::GetDirectoryName($source)
        $projectRoot = Find-ProjectRoot -StartDirectory $sourceDirectory
        $dateDirectory = Join-Path $projectRoot (Join-Path '_dev\compile_logs' (Get-Date -Format 'yyyy-MM-dd'))
        New-Item -ItemType Directory -Path $dateDirectory -Force | Out-Null
        $logName = '{0}.compile_{1}.log' -f ([IO.Path]::GetFileNameWithoutExtension($source)), (Get-Date -Format 'yyyyMMdd_HHmmss')
        $LogPath = Get-UniqueLogPath -Directory $dateDirectory -FileName $logName
    }
    $log = [IO.Path]::GetFullPath($LogPath)
    $logDirectory = [IO.Path]::GetDirectoryName($log)
    if(!(Test-Path -LiteralPath $logDirectory)) {
        New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
    }
    if($customLogPath) {
        Remove-Item -LiteralPath $log -Force -ErrorAction SilentlyContinue
    }

    Write-Host "Compiling: $source"
    Write-Host "MetaEditor: $MetaEditorPath"
    Write-Host "Compile log: $log"
    $process = Start-Process -FilePath $MetaEditorPath -ArgumentList @("/compile:$source", "/log:$log") -Wait -PassThru -NoNewWindow
    $processCode = $process.ExitCode
    if(!(Test-Path -LiteralPath $log)) { throw "MetaEditor did not create a compile log: $log" }
    $content = Get-Content -LiteralPath $log -Raw
    $content
    $summary = [regex]::Match($content, 'Result:\s*(\d+)\s+errors?,\s*(\d+)\s+warnings?(?:,\s*([^\r\n]+))?', 'IgnoreCase')
    if(!$summary.Success) { throw 'Could not parse MetaEditor compile summary; inspect the printed log.' }
    $errors = [int]$summary.Groups[1].Value
    $warnings = [int]$summary.Groups[2].Value
    Write-Host "Parsed result: errors=$errors warnings=$warnings $($summary.Groups[3].Value)"
    if($processCode -ne 0) { Write-Warning "MetaEditor process code was $processCode; compile result is taken from its log." }
    if($warnings -gt 0) { Write-Warning 'Warnings exist. This script cannot determine whether they are new without a baseline.' }
    # MetaEditor在部分终端版本会在日志成功后返回非零进程码；以日志中的errors为最终编译依据。
    if($errors -gt 0) { exit 1 }
    exit 0
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
