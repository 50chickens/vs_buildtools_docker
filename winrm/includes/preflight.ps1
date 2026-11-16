function Invoke-PreflightCheck($configuration)
{
    $valuesToCheck = @('remoteBaseFolder', 'configurationName')
    $valuesToCheck |% {
        $valueName = $_
        $value     = $configuration.$valueName
        if ([string]::IsNullOrEmpty($value))
        {
            throw "$valueName is required in settings.json."
        }
    }

    $remoteHosts = $configuration.remoteHosts
    if ($remoteHosts.Count -eq 0)
    {
        throw "remoteHosts is empty in settings.json, so no host would be configured."
    }

    $skipUpload = $configuration.skipUpload
    if ($skipUpload)
    {
        return
    }

    $localFolders  = @($configuration.localFolders |? { !([string]::IsNullOrEmpty($_)) })
    $configFolders = @($configuration.configurationFoldersToUploadToRemote |? { !([string]::IsNullOrEmpty($_)) })
    $folderCount   = $localFolders.Count + $configFolders.Count
    if ($folderCount -eq 0)
    {
        throw "localFolders and configurationFoldersToUploadToRemote are empty, so the upload would copy nothing."
    }

    if ($configFolders.Count -gt 0 -and [string]::IsNullOrEmpty($configuration.LocalConfigBaseFolder))
    {
        throw "localConfigBaseFolder is required when configurationFoldersToUploadToRemote is set."
    }
}
