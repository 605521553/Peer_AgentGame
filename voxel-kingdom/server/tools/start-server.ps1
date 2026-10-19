param([int]$Port = 8765, [int]$TlsPort = 8766, [string]$Bind = '0.0.0.0')
$ErrorActionPreference = 'Stop'
$taskProjectRoot = Split-Path $PSScriptRoot -Parent
Set-Location -LiteralPath $taskProjectRoot
$taskPythonPath = Join-Path (Split-Path $taskProjectRoot -Parent) '.venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $taskPythonPath)) { $taskPythonPath = Join-Path $taskProjectRoot '.venv\Scripts\python.exe'; if (-not (Test-Path -LiteralPath $taskPythonPath)) { python -m venv .venv } }
& $taskPythonPath -m pip install -r requirements.txt
if ($LASTEXITCODE -ne 0) { throw 'Backend dependencies could not be installed' }
Write-Output ('Local: http://localhost:' + $Port + ' . LAN: https://your-LAN-address:' + $TlsPort)
Write-Output 'LAN uses a self-signed local certificate. No system root certificate is installed.'
& $taskPythonPath -m backend.run --bind $Bind --port $Port --tls-port $TlsPort
