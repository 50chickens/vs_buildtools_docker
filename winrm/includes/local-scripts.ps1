function Get-LocalScriptPath($configuration, $scriptEntry)
{
    if ($scriptEntry.fullPath)
    {
        return $scriptEntry.filePath
    }
    return "$($configuration.ScriptFolder)\$($scriptEntry.filePath)"
}

function Invoke-LocalScriptList($configuration, $scripts)
{
    $scripts |? { $_.enabled } |% {
        $scriptEntry = $_
        $scriptPath  = Get-LocalScriptPath $configuration $scriptEntry
        Write-Log "Running $scriptPath"
        & $scriptPath

        $isPowerShellScript = $scriptPath -like '*.ps1'
        if ($isPowerShellScript)
        {
            Write-Log "Finished $scriptPath"
            return
        }

        if ($LASTEXITCODE -ne 0)
        {
            throw "$scriptPath exited with code $LASTEXITCODE"
        }
        Write-Log "Finished $scriptPath"
    }
}

function Invoke-LocalScripts($configuration)
{
    $localScripts = $configuration.localScripts
    Invoke-LocalScriptList $configuration $localScripts
}
