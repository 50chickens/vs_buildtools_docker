function Get-HostConfigurations($configuration)
{
    $remoteHosts        = $configuration.remoteHosts
    $hostConfigurations = $remoteHosts |% {
        $remoteHost        = $_
        $hostConfiguration = $configuration | Select-Object *
        $hostConfiguration | Add-Member -NotePropertyName 'RemoteHost' -NotePropertyValue $remoteHost -Force
        return $hostConfiguration
    }
    return $hostConfigurations
}

function Test-RemoteHostAvailable($configuration)
{
    $remoteHost  = $configuration.RemoteHost
    $remotePort  = $configuration.remotePort
    $isAvailable = Test-NetConnection -ComputerName $remoteHost -Port $remotePort -InformationLevel Quiet
    return $isAvailable
}

function Wait-RemoteHostAvailable($configuration)
{
    $remoteHost           = $configuration.RemoteHost
    $remotePort           = $configuration.remotePort
    $retryIntervalSeconds = $configuration.retryIntervalSeconds
    $timeoutSeconds       = $configuration.timeoutSeconds
    $deadline             = (Get-Date).AddSeconds($timeoutSeconds)
    Write-Log "Waiting up to $timeoutSeconds seconds for $remoteHost port $remotePort"

    Start-Sleep -Seconds $retryIntervalSeconds
    $hostIsAvailable = Test-RemoteHostAvailable $configuration
    while (!$hostIsAvailable)
    {
        if ((Get-Date) -gt $deadline)
        {
            throw "$remoteHost port $remotePort did not answer within $timeoutSeconds seconds."
        }
        Start-Sleep -Seconds $retryIntervalSeconds
        $hostIsAvailable = Test-RemoteHostAvailable $configuration
    }

    Write-Log "$remoteHost port $remotePort is answering"
}
