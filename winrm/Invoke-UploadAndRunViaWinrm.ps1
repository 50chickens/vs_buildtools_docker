$ErrorActionPreference = 'Stop'
$VerbosePreference     = 'SilentlyContinue'
Set-Location $PSScriptRoot

Get-ChildItem -Path "includes" -Filter "*.ps1" -Recurse |% {
    Write-Verbose "Dot-sourcing $($_.FullName)"
    . $_.FullName
}

function Get-Configuration
{
    $scriptFolder          = (Get-Item ".").FullName
    $settingsPath          = "$scriptFolder\settings.json"
    $settings              = Get-Content -Path $settingsPath -Raw | ConvertFrom-Json
    $secretsStore          = $env:SECRETS_STORE
    $credentialName        = $settings.credentialFileName
    $localBaseFolder       = (Get-Item "$scriptFolder\$($settings.localBaseFolder)").FullName
    $sealedCredentialPath  = "$secretsStore\$credentialName.user.dpapi"
    $credentialPlaceholder = 'sealed'
    $chunkSizeBytes        = $settings.chunkSizeMb * 1MB

    $configuration = $settings
    $configuration | Add-Member -NotePropertyName 'ScriptFolder'          -NotePropertyValue $scriptFolder          -Force
    $configuration | Add-Member -NotePropertyName 'LocalBaseFolder'       -NotePropertyValue $localBaseFolder       -Force
    $configuration | Add-Member -NotePropertyName 'SealedCredentialPath'  -NotePropertyValue $sealedCredentialPath  -Force
    $configuration | Add-Member -NotePropertyName 'CredentialPlaceholder' -NotePropertyValue $credentialPlaceholder -Force
    $configuration | Add-Member -NotePropertyName 'ChunkSizeBytes'        -NotePropertyValue $chunkSizeBytes        -Force
    return $configuration
}

$configuration = Get-Configuration
Invoke-PreflightCheck $configuration
Invoke-LocalScripts $configuration

$hostConfigurations = Get-HostConfigurations $configuration
$hostConfigurations |% {
    $configuration = $_
    $configuration = Connect-UploadSession $configuration
    Invoke-UploadFolder $configuration
    Disconnect-UploadSession $configuration
    Invoke-RemoteScript $configuration
}

Invoke-ValidationScripts $configuration
