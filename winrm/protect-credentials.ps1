$ErrorActionPreference = 'Stop'
$VerbosePreference     = 'SilentlyContinue'
Set-Location $PSScriptRoot

function Write-Log($message)
{
    Write-Host "[$([DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss'))] $message"
}

function Get-Configuration
{
    $scriptFolder   = (Get-Item ".").FullName
    $settingsPath   = "$scriptFolder\settings.json"
    $settings       = Get-Content -Path $settingsPath -Raw | ConvertFrom-Json
    $secretsStore   = $env:SECRETS_STORE
    $credentialName = $settings.credentialFileName
    $plainPath      = "$secretsStore\$credentialName.txt"
    $sealedPath     = "$secretsStore\$credentialName.user.dpapi"
    $credentialPlaceholder = 'sealed'

    $configuration = $settings
    $configuration | Add-Member -NotePropertyName 'PlainCredentialPath'   -NotePropertyValue $plainPath             -Force
    $configuration | Add-Member -NotePropertyName 'SealedCredentialPath'  -NotePropertyValue $sealedPath            -Force
    $configuration | Add-Member -NotePropertyName 'CredentialPlaceholder' -NotePropertyValue $credentialPlaceholder -Force
    return $configuration
}

function Invoke-ProtectCredential($configuration)
{
    $plainPath  = $configuration.PlainCredentialPath
    $sealedPath = $configuration.SealedCredentialPath
    $plainText  = (Get-Content -Path $plainPath -Raw).Trim()

    $credentialData = $plainText | ConvertFrom-Json
    $userName       = $credentialData.username
    Write-Log "The plaintext is json for user $userName"

    Write-Log "Sealing $plainPath"
    $secureText = ConvertTo-SecureString -String $plainText -AsPlainText -Force
    $sealedText = ConvertFrom-SecureString -SecureString $secureText
    Set-Content -Path $sealedPath -Value $sealedText

    $writtenText   = (Get-Content -Path $sealedPath -Raw).Trim()
    $writtenSecure = ConvertTo-SecureString -String $writtenText
    $placeholder   = $configuration.CredentialPlaceholder
    $recoveredText = [pscredential]::new($placeholder, $writtenSecure).GetNetworkCredential().Password
    if ($recoveredText -ne $plainText)
    {
        throw "The sealed credential at $sealedPath does not unseal to the original content."
    }

    Remove-Item -Path $plainPath
    Write-Log "Sealed to $sealedPath and removed the plaintext file."
}

$configuration = Get-Configuration
Invoke-ProtectCredential $configuration
