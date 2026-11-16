$ErrorActionPreference = 'Stop'
$VerbosePreference     = 'SilentlyContinue'
Set-Location $PSScriptRoot

function Write-Log($message)
{
    Write-Host "[$([DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss'))] $message"
}

$computerSystem  = Get-CimInstance -ClassName Win32_ComputerSystem
$operatingSystem = Get-CimInstance -ClassName Win32_OperatingSystem
$cachedAssetsFolder = (Get-Item "..\cached_assets").FullName
$cachedAssets = Get-ChildItem -Path $cachedAssetsFolder -File

Write-Log "noop ran on $($computerSystem.Name) as $($computerSystem.UserName)"
Write-Log "noop runs from $PSScriptRoot"
Write-Log "os version $($operatingSystem.Version)"
Write-Log "cached assets uploaded: $($cachedAssets.Count)"
