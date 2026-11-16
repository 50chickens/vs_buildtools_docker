$ErrorActionPreference = 'Stop'
$VerbosePreference     = 'SilentlyContinue'
Set-Location $PSScriptRoot

function Write-Log($message)
{
    Write-Host "[$([DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss'))] $message"
}

function Get-Configuration
{
    $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem
    $computerName   = $computerSystem.Name
    $windowsFeatures = @('Containers')

    $configuration = [pscustomobject]@{
        ComputerName       = $computerName
        WindowsFeatures    = $windowsFeatures
        RebootDelaySeconds = 2
    }
    return $configuration
}

function Invoke-FeatureInstall($configuration)
{
    $windowsFeatures = $configuration.WindowsFeatures
    Write-Log "Installing windows features $($windowsFeatures -join ', ')"
    $featureResult = Install-WindowsFeature -Name $windowsFeatures -IncludeManagementTools
    $restartNeeded = $featureResult.RestartNeeded
    Write-Log "Feature install complete, restart needed: $restartNeeded"
    $configuration | Add-Member -NotePropertyName 'RestartNeeded' -NotePropertyValue $restartNeeded -Force
    return $configuration
}

function Test-ShouldRestart($configuration)
{
    $restartNeeded = $configuration.RestartNeeded
    if ($restartNeeded -eq 'Yes')
    {
        return $true
    }
    Write-Log "No restart needed"
    return $false
}

function Invoke-Restart($configuration)
{
    if (!(Test-ShouldRestart $configuration))
    {
        return
    }

    $computerName       = $configuration.ComputerName
    $rebootDelaySeconds = $configuration.RebootDelaySeconds
    Write-Log "Restarting $computerName in $rebootDelaySeconds seconds"

    $rebootArguments = @('/r', '/t', $rebootDelaySeconds, '/f')
    $null = Start-Process -FilePath 'shutdown.exe' -ArgumentList $rebootArguments
}

$configuration = Get-Configuration
$configuration = Invoke-FeatureInstall $configuration
Invoke-Restart $configuration
