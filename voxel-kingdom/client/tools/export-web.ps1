param([string]$GodotPath = 'D:\Godot4.7.2\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe')
$ErrorActionPreference = 'Stop'
$taskProjectRoot = Split-Path $PSScriptRoot -Parent
$taskRepoRoot = Split-Path $taskProjectRoot -Parent
$taskBuildPath = Join-Path $taskRepoRoot 'build\client-web'
New-Item -ItemType Directory -Path $taskBuildPath -Force | Out-Null
& $GodotPath --headless --path $taskProjectRoot --editor --quit
if ($LASTEXITCODE -ne 0) { throw 'Godot import failed' }
& $GodotPath --headless --path $taskProjectRoot --export-release Web (Join-Path $taskBuildPath 'index.html')
if ($LASTEXITCODE -ne 0) { throw 'Godot Web export failed' }
$taskPython = Join-Path $taskRepoRoot '.venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $taskPython)) { $taskPython = (Get-Command python -ErrorAction Stop).Source }
& $taskPython (Join-Path $taskRepoRoot 'tools\version_web.py')
if ($LASTEXITCODE -ne 0) { throw 'Web asset versioning failed' }
Write-Output ('Web export ready: ' + $taskBuildPath)
