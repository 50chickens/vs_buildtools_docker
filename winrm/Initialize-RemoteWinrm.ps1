$ErrorActionPreference = 'Stop'
$VerbosePreference     = 'SilentlyContinue'
Set-Location $PSScriptRoot

function Write-Log($message)
{
    Write-Host "[$([DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss'))] $message"
}

function Get-Configuration
{
    $scriptFolder          = (Get-Item ".").FullName
    $settingsPath          = "$scriptFolder\settings.json"
    $settings              = Get-Content -Path $settingsPath -Raw | ConvertFrom-Json
    $secretsStore          = $env:SECRETS_STORE
    $credentialName        = $settings.credentialFileName
    $binFolder             = "$scriptFolder\bin"
    $psToolsZipPath        = "$binFolder\PSTools.zip"
    $psExecPath            = "$binFolder\PsExec64.exe"
    $payloadScriptPath     = "$scriptFolder\assets\configure-remote-winrm.ps1"
    $sealedCredentialPath  = "$secretsStore\$credentialName.user.dpapi"
    $credentialPlaceholder = 'sealed'

    $configuration = $settings
    $configuration | Add-Member -NotePropertyName 'BinFolder'             -NotePropertyValue $binFolder             -Force
    $configuration | Add-Member -NotePropertyName 'PsToolsZipPath'        -NotePropertyValue $psToolsZipPath        -Force
    $configuration | Add-Member -NotePropertyName 'PsExecPath'            -NotePropertyValue $psExecPath            -Force
    $configuration | Add-Member -NotePropertyName 'PayloadScriptPath'     -NotePropertyValue $payloadScriptPath     -Force
    $configuration | Add-Member -NotePropertyName 'SealedCredentialPath'  -NotePropertyValue $sealedCredentialPath  -Force
    $configuration | Add-Member -NotePropertyName 'CredentialPlaceholder' -NotePropertyValue $credentialPlaceholder -Force
    return $configuration
}

function Install-PsExec($configuration)
{
    $psExecPath     = $configuration.PsExecPath
    $psToolsUrl     = $configuration.psToolsUrl
    $binFolder      = $configuration.BinFolder
    $psToolsZipPath = $configuration.PsToolsZipPath
    if (Test-Path -Path $psExecPath)
    {
        Write-Log "PsExec is already present at $psExecPath"
        return
    }

    Write-Log "Downloading $psToolsUrl to $psToolsZipPath"
    $null = New-Item -ItemType Directory -Path $binFolder -Force
    Invoke-WebRequest -Uri $psToolsUrl -OutFile $psToolsZipPath
    Expand-Archive -Path $psToolsZipPath -DestinationPath $binFolder -Force
    Write-Log "Expanded PsTools into $binFolder"
}

function Get-RemoteCredential($configuration)
{
    $sealedCredentialPath  = $configuration.SealedCredentialPath
    $credentialPlaceholder = $configuration.CredentialPlaceholder
    Write-Log "Reading the sealed credential at $sealedCredentialPath"

    $sealedText     = (Get-Content -Path $sealedCredentialPath -Raw).Trim()
    $unsealedSecure = ConvertTo-SecureString -String $sealedText
    $unsealedText   = [pscredential]::new($credentialPlaceholder, $unsealedSecure).GetNetworkCredential().Password
    $credentialData = $unsealedText | ConvertFrom-Json
    $userName       = $credentialData.username
    $password       = ConvertTo-SecureString -String $credentialData.password -AsPlainText -Force
    $credential     = [pscredential]::new($userName, $password)
    return $credential
}

function Invoke-RemoteConfiguration($configuration)
{
    $remoteHost        = $configuration.remoteHost
    $psExecPath        = $configuration.PsExecPath
    $payloadScriptPath = $configuration.PayloadScriptPath
    $payloadText       = Get-Content -Path $payloadScriptPath -Raw
    $payloadBytes      = [System.Text.Encoding]::Unicode.GetBytes($payloadText)
    $encodedCommand    = [Convert]::ToBase64String($payloadBytes)
    $credential        = Get-RemoteCredential $configuration
    $userName          = $credential.UserName
    $password          = $credential.GetNetworkCredential().Password
    Write-Log "Configuring WinRM on $remoteHost as $userName with PsExec"

    $psExecArguments = @(
        "\\$remoteHost",
        '-accepteula',
        '-nobanner',
        '-s',
        '-u', $userName,
        '-p', $password,
        'powershell.exe',
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-EncodedCommand', $encodedCommand
    )
    & $psExecPath @psExecArguments
    if ($LASTEXITCODE -ne 0)
    {
        throw "PsExec exited with code $LASTEXITCODE while configuring $remoteHost"
    }
}

$configuration = Get-Configuration
Install-PsExec $configuration
Invoke-RemoteConfiguration $configuration
