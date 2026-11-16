$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

$scriptsDir = Join-Path $PSScriptRoot "..\src\scripts"

& "$scriptsDir\invoke-application-tests.ps1"
& "$scriptsDir\invoke-docker.ps1"
& "$scriptsDir\invoke-deployment.ps1"
& "$scriptsDir\invoke-deployment-test.ps1"
