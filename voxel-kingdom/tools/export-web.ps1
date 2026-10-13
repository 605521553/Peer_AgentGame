param([string]$GodotPath = 'D:\Godot4.7.2\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe')
$ErrorActionPreference = 'Stop'
$taskProjectRoot = Split-Path $PSScriptRoot -Parent
$taskBuildPath = Join-Path $taskProjectRoot 'build\web'
New-Item -ItemType Directory -Path $taskBuildPath -Force | Out-Null
& $GodotPath --headless --path $taskProjectRoot --editor --quit
if ($LASTEXITCODE -ne 0) { throw 'Godot import failed' }
& $GodotPath --headless --path $taskProjectRoot --export-release Web (Join-Path $taskBuildPath 'index.html')
if ($LASTEXITCODE -ne 0) { throw 'Godot Web export failed' }
Write-Output ('Web export ready: ' + $taskBuildPath)
