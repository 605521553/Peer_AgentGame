param([int]$Port = 8765, [int]$TlsPort = 8766)
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path $PSScriptRoot -Parent
$taskPrivatePath = Join-Path $env:LOCALAPPDATA 'VoxelKingdom'
$taskPython = Join-Path (Split-Path $taskRoot -Parent) '.venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $taskPython)) { $taskPython = Join-Path $taskRoot '.venv\Scripts\python.exe' }
if (-not (Test-Path -LiteralPath $taskPython)) { throw 'Run tools/start-server.ps1 once to install dependencies.' }
if (Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue) {
    Write-Output ('Port ' + $Port + ' is already listening. Existing service was left running.')
    exit 0
}
New-Item -ItemType Directory -Path $taskPrivatePath -Force | Out-Null
$taskProcess = Start-Process -FilePath $taskPython -ArgumentList @('-m', 'backend.run', '--port', $Port, '--tls-port', $TlsPort) -WorkingDirectory $taskRoot -WindowStyle Hidden -RedirectStandardOutput (Join-Path $taskPrivatePath 'server.stdout.log') -RedirectStandardError (Join-Path $taskPrivatePath 'server.stderr.log') -PassThru
[System.IO.File]::WriteAllText((Join-Path $taskPrivatePath 'server.pid'), [string]$taskProcess.Id)
for ($taskAttempt = 0; $taskAttempt -lt 20; $taskAttempt++) {
    Start-Sleep -Milliseconds 300
    try {
        $taskHealth = Invoke-RestMethod -Uri ('http://127.0.0.1:' + $Port + '/api/health') -TimeoutSec 1
        if ($taskHealth.ok) { Write-Output ('Background service running. PID=' + $taskProcess.Id); exit 0 }
    } catch { }
}
throw ('Backend did not start. Inspect private logs in ' + $taskPrivatePath)
