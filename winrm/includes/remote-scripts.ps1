function Get-RemoteScriptPath($configuration, $remoteScript)
{
    if ($remoteScript.fullPath)
    {
        return $remoteScript.filePath
    }
    return "$($configuration.remoteBaseFolder)\$($remoteScript.filePath)"
}

function Get-ScriptConfigurationName($configuration, $remoteScript)
{
    if ([string]::IsNullOrEmpty($remoteScript.configurationName))
    {
        return $configuration.configurationName
    }
    return $remoteScript.configurationName
}

function Test-RemoteRebootPending($session)
{
    $rebootPending = Invoke-Command -Session $session -ScriptBlock {
        Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
    }
    return $rebootPending
}

function Invoke-RemoteReboot($session)
{
    Write-Log "Triggering an asynchronous restart"
    $null = Invoke-Command -Session $session -ScriptBlock {
        $arguments = @{ CommandLine = 'shutdown.exe /r /t 2 /f' }
        $null = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments $arguments
    }
}

function Invoke-RemoteScript($configuration)
{
    $remoteScripts = $configuration.remoteScripts
    $remoteScripts |? { $_.enabled } |% {
        $remoteScript = $_
        Invoke-RemoteScriptFile $configuration $remoteScript
    }
}

function Invoke-RemoteScriptFile($configuration, $remoteScript)
{
    $remoteScriptPath  = Get-RemoteScriptPath $configuration $remoteScript
    $configurationName = Get-ScriptConfigurationName $configuration $remoteScript
    $session           = New-RemoteSession $configuration $configurationName
    Write-Log "Running $remoteScriptPath"

    try
    {
        $remoteOutput = Invoke-Command -Session $session -ScriptBlock {
            param($path)
            Set-Location (Split-Path -Path $path -Parent)
            & $path
        } -ArgumentList $remoteScriptPath
    }
    catch
    {
        Write-Log "Remote script failed: $($_.Exception.Message)"
        Write-Log "Remote stack trace: $($_.ScriptStackTrace)"
        throw
    }

    $remoteOutput |% { Write-Log "$_" }
    Write-Log "Finished $remoteScriptPath"

    $reboot  = $remoteScript.reboot
    $pending = $false
    if ($reboot)
    {
        $pending = Test-RemoteRebootPending $session
        Write-Log "Reboot pending after running $remoteScriptPath is $pending"
    }

    if ($pending)
    {
        Invoke-RemoteReboot $session
        Remove-PSSession -Session $session
        Invoke-LocalScriptList $configuration $remoteScript.localPostScripts
        Wait-RemoteHostAvailable $configuration
        return
    }

    Remove-PSSession -Session $session
}
