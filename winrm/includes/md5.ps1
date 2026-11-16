function Test-IsExcludedFromHash($configuration, $remotePath)
{
    $excludePatterns = $configuration.excludeRemoteFolderPatternsFromMD5
    $isExcluded      = $false
    $excludePatterns |% {
        $pattern = $_
        if ($remotePath -like $pattern)
        {
            $isExcluded = $true
        }
    }
    return $isExcluded
}

function Get-RemoteFileHashMap($configuration, $remotePaths)
{
    $session     = $configuration.UploadSession
    $pathsToHash = $remotePaths |? { !(Test-IsExcludedFromHash $configuration $_) }
    $fileHashes  = Invoke-Command -Session $session -ScriptBlock {
        param($paths)
        $hashMap = @{}
        $paths |% {
            $path = $_
            if (Test-Path -Path $path)
            {
                $hashMap[$path] = (Get-FileHash -Path $path -Algorithm MD5).Hash
            }
        }
        return $hashMap
    } -ArgumentList (,$pathsToHash)
    return $fileHashes
}

function Test-IsFileUnchanged($localFile, $remoteFileHashes, $remotePath)
{
    $localHash   = (Get-FileHash -Path $localFile.FullName -Algorithm MD5).Hash
    $remoteHash  = $remoteFileHashes[$remotePath]
    $isUnchanged = $localHash -eq $remoteHash
    return $isUnchanged
}
