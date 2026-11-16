function Test-IsLocalFileIgnored($configuration, $localFile)
{
    $ignoreTypes = $configuration.ignoreFileTypesIfExistsOnLocal
    $sizeLimitMb = $configuration.ignoreFilesLargerThanMB

    if ($ignoreTypes -contains $localFile.Extension)
    {
        Write-Log "Skipping $($localFile.Name), $($localFile.Extension) is in ignoreFileTypesIfExistsOnLocal"
        return $true
    }

    if ($sizeLimitMb -gt 0 -and $localFile.Length -gt ($sizeLimitMb * 1MB))
    {
        Write-Log "Skipping $($localFile.Name), it is larger than $sizeLimitMb MB"
        return $true
    }

    return $false
}

function Test-IsRemoteFileProtected($configuration, $remoteFileHashes, $localFile, $remotePath)
{
    $protectedTypes = $configuration.ignoreFileTypesIfExistsOnRemote
    if ($protectedTypes -contains $localFile.Extension)
    {
        $existsOnRemote = $remoteFileHashes.ContainsKey($remotePath)
        if ($existsOnRemote)
        {
            Write-Log "Skipping $($localFile.Name), it already exists at $remotePath"
            return $true
        }
    }

    return $false
}
