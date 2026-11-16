$ErrorActionPreference = 'Stop'

function Write-Log($message)
{
    Write-Host "[$([DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss'))] $message"
}

function Get-Configuration
{
    $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem
    $computerName   = $computerSystem.Name

    $configuration = [pscustomobject]@{
        ComputerName     = $computerName
        CertSubject      = "CN=$computerName"
        CertStorePath    = 'Cert:\LocalMachine\My'
        CertYears        = 5
        ListenerPort     = 5986
        FirewallRuleName = 'WinRM-HTTPS-In'
        ListenerRoot     = 'WSMan:\localhost\Listener'
    }
    return $configuration
}

function Add-Certificate($configuration)
{
    $certStorePath = $configuration.CertStorePath
    $certSubject   = $configuration.CertSubject
    $computerName  = $configuration.ComputerName
    $certYears     = $configuration.CertYears
    Write-Log "Looking for a certificate with subject $certSubject in $certStorePath"

    $certificates = Get-ChildItem -Path $certStorePath |? { $_.Subject -eq $certSubject }
    $certificate  = $certificates | Select-Object -First 1
    if ($null -eq $certificate)
    {
        Write-Log "Creating a self-signed certificate for $computerName"
        $certificate = New-SelfSignedCertificate -DnsName $computerName -CertStoreLocation $certStorePath -NotAfter (Get-Date).AddYears($certYears)
    }

    $thumbprint = $certificate.Thumbprint
    Write-Log "Using certificate $thumbprint expiring $($certificate.NotAfter)"
    $configuration | Add-Member -NotePropertyName 'CertificateThumbprint' -NotePropertyValue $thumbprint -Force
    return $configuration
}

function Add-HttpsListener($configuration)
{
    $listenerRoot = $configuration.ListenerRoot
    $listenerPort = $configuration.ListenerPort
    $thumbprint   = $configuration.CertificateThumbprint
    Write-Log "Replacing the https listener on port $listenerPort"

    $httpsListeners = Get-ChildItem -Path $listenerRoot |? { $_.Keys -contains 'Transport=HTTPS' }
    $httpsListeners |% {
        $listener = $_
        Write-Log "Removing listener $($listener.PSChildName)"
        Remove-Item -Path $listener.PSPath -Recurse -Force
    }

    $null = New-Item -Path $listenerRoot -Transport HTTPS -Address * -CertificateThumbprint $thumbprint -Port $listenerPort -Force
    Write-Log "Created the https listener on port $listenerPort with thumbprint $thumbprint"
}

function Add-FirewallRule($configuration)
{
    $firewallRuleName = $configuration.FirewallRuleName
    $listenerPort     = $configuration.ListenerPort
    $existingRule     = Get-NetFirewallRule -Name $firewallRuleName -ErrorAction SilentlyContinue
    if ($null -ne $existingRule)
    {
        Write-Log "Updating firewall rule $firewallRuleName"
        Set-NetFirewallRule -Name $firewallRuleName -LocalPort $listenerPort -Protocol TCP -Direction Inbound -Action Allow
        return
    }

    Write-Log "Creating firewall rule $firewallRuleName"
    $null = New-NetFirewallRule -Name $firewallRuleName -DisplayName "WinRM HTTPS ($listenerPort)" -Direction Inbound -Protocol TCP -LocalPort $listenerPort -Action Allow
}

$configuration = Get-Configuration
$configuration = Add-Certificate $configuration
Add-HttpsListener $configuration
Add-FirewallRule $configuration
Write-Log "WinRM https is configured on port $($configuration.ListenerPort)"
