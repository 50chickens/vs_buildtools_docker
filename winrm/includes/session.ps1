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

function Get-SessionOption($configuration)
{
    $useSsl               = $configuration.useSsl
    $skipCertificateCheck = $configuration.skipCertificateCheck
    $openTimeoutSeconds   = $configuration.openTimeoutSeconds
    $openTimeoutMs        = [int]($openTimeoutSeconds * 1000)

    if ($useSsl -and $skipCertificateCheck)
    {
        $sessionOption = New-PSSessionOption -SkipCACheck -SkipCNCheck -SkipRevocationCheck -OpenTimeout $openTimeoutMs
        return $sessionOption
    }

    $sessionOption = New-PSSessionOption -OpenTimeout $openTimeoutMs
    return $sessionOption
}

function New-RemoteSession($configuration, $configurationName)
{
    $remoteHost    = $configuration.RemoteHost
    $remotePort    = $configuration.remotePort
    $useSsl        = $configuration.useSsl
    $credential    = Get-RemoteCredential $configuration
    $sessionOption = Get-SessionOption $configuration
    Write-Log "Opening a WinRM session to $remoteHost port $remotePort as $($credential.UserName) on $configurationName"

    $sessionParameters = @{
        ComputerName      = $remoteHost
        Port              = $remotePort
        UseSSL            = $useSsl
        Credential        = $credential
        ConfigurationName = $configurationName
        SessionOption     = $sessionOption
    }
    $session = New-PSSession @sessionParameters
    Write-Log "Session $($session.Id) established with $remoteHost"
    return $session
}

function Connect-UploadSession($configuration)
{
    $configurationName = $configuration.configurationName
    $session           = New-RemoteSession $configuration $configurationName
    $configuration | Add-Member -NotePropertyName 'UploadSession' -NotePropertyValue $session -Force
    return $configuration
}

function Disconnect-UploadSession($configuration)
{
    $session = $configuration.UploadSession
    Write-Log "Closing session $($session.Id)"
    Remove-PSSession -Session $session
}
