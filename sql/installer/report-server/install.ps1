$ErrorActionPreference = 'Stop'
$VerbosePreference     = 'SilentlyContinue'
Set-Location $PSScriptRoot

function Write-Log($message)
{
    Write-Host "[$([DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss'))] $message"
}

function Get-Configuration
{
    $scriptFolder       = (Get-Item ".").FullName
    $settingsPath       = "$scriptFolder\settings.json"
    $settings           = Get-Content -Path $settingsPath -Raw | ConvertFrom-Json
    $mediaFolderPath    = $settings.mediaFolderPath
    $instanceName       = $settings.instanceName
    $edition            = $settings.edition
    $installerPath      = "$mediaFolderPath\$($settings.installerFileName)"
    $installerArguments = @(
        '/quiet',
        '/ACTION=INSTALL',
        "/INSTANCENAME=$instanceName",
        "/EDITION=$edition",
        '/IAcceptLicenseTerms'
    )

    $configuration = $settings
    $configuration | Add-Member -NotePropertyName 'MediaFolderPath'    -NotePropertyValue $mediaFolderPath    -Force
    $configuration | Add-Member -NotePropertyName 'InstallerPath'      -NotePropertyValue $installerPath      -Force
    $configuration | Add-Member -NotePropertyName 'InstallerArguments' -NotePropertyValue $installerArguments -Force
    return $configuration
}

function Invoke-Installer($configuration)
{
    $installerPath      = $configuration.InstallerPath
    $installerArguments = $configuration.InstallerArguments
    Write-Log "Installing the report server bundle from $installerPath"
    $installerProcess  = Start-Process -FilePath $installerPath -ArgumentList $installerArguments -Wait -PassThru
    $installerExitCode = $installerProcess.ExitCode
    Write-Log "Installer exited with $installerExitCode"
    if ($installerExitCode -ne 0)
    {
        throw "Report server installer failed with exit code $installerExitCode"
    }
}

$configuration = Get-Configuration
Invoke-Installer $configuration
