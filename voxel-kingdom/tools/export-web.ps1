# Compatibility entry point; implementation belongs to the client subproject.
& (Join-Path $PSScriptRoot '..\client\tools\export-web.ps1') @args
exit $LASTEXITCODE
