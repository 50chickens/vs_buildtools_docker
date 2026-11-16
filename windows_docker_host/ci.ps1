$ErrorActionPreference = 'Stop'
$VerbosePreference     = 'SilentlyContinue'
Set-Location $PSScriptRoot

function Write-Log($message)
{
    Write-Host "[$([DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss'))] $message"
}

function Get-Configuration
{
    $scriptFolder      = (Get-Item ".").FullName
    $settingsPath      = "$scriptFolder\settings.json"
    $settings          = Get-Content -Path $settingsPath -Raw | ConvertFrom-Json
    $cachedAssetsFolder = "$scriptFolder\cached_assets"
    $winrmScriptPath   = (Get-Item "..\winrm\Invoke-UploadAndRunViaWinrm.ps1").FullName

    $configuration = $settings
    $configuration | Add-Member -NotePropertyName 'CachedAssetsFolder' -NotePropertyValue $cachedAssetsFolder -Force
    $configuration | Add-Member -NotePropertyName 'WinrmScriptPath'    -NotePropertyValue $winrmScriptPath    -Force
    return $configuration
}

function Invoke-CachedAssetDownload($configuration)
{
    $cachedAssetsFolder = $configuration.CachedAssetsFolder
    $cachedAssets       = $configuration.cachedAssets

    $cachedAssets |? { $_.enabled } |% {
        $cachedAsset = $_
        $assetPath   = "$cachedAssetsFolder\$($cachedAsset.fileName)"
        if (Test-Path -Path $assetPath)
        {
            Write-Log "Cached asset present at $assetPath"
            return
        }

        Write-Log "Downloading $($cachedAsset.url) to $assetPath"
        $null = New-Item -ItemType Directory -Path $cachedAssetsFolder -Force
        Invoke-WebRequest -Uri $cachedAsset.url -OutFile $assetPath
    }
}

function Invoke-RemoteConfiguration($configuration)
{
    $winrmScriptPath = $configuration.WinrmScriptPath
    Write-Log "Running $winrmScriptPath"
    & $winrmScriptPath
}

$configuration = Get-Configuration
Invoke-CachedAssetDownload $configuration
Invoke-RemoteConfiguration $configuration
