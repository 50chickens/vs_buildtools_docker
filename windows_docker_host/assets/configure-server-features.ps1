$ErrorActionPreference = 'Stop'
$VerbosePreference     = 'SilentlyContinue'
Set-Location $PSScriptRoot

function Write-Log($message)
{
    Write-Host "[$([DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss'))] $message"
}

function Get-Configuration
{
    $windowsFeatures = @('Containers')

    $configuration = [pscustomobject]@{
        WindowsFeatures = $windowsFeatures
    }
    return $configuration
}

function Invoke-FeatureInstall($configuration)
{
    $windowsFeatures = $configuration.WindowsFeatures
    Write-Log "Installing windows features $($windowsFeatures -join ', ')"
    $featureResult = Install-WindowsFeature -Name $windowsFeatures -IncludeManagementTools
    Write-Log "Feature install complete, restart needed: $($featureResult.RestartNeeded)"
}

$configuration = Get-Configuration
Invoke-FeatureInstall $configuration
