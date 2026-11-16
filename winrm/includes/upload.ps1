function Get-RelativePath($baseFolder, $fullPath)
{
    $relativePath = $fullPath.Substring($baseFolder.Length).TrimStart('\')
    return $relativePath
}

function Get-ConfigurationFolderSource($configuration, $folder)
{
    $configBaseFolder  = $configuration.LocalConfigBaseFolder
    $targetEnvironment = $configuration.targetEnvironment
    $overlayFolder     = "$configBaseFolder\$targetEnvironment\$folder"

    if (Test-Path -Path $overlayFolder)
    {
        Write-Log "Using the $targetEnvironment overlay for $folder"
        return $overlayFolder
    }

    return "$configBaseFolder\$folder"
}

function Add-RemoteFolders($configuration, $localFolder, $remoteFolder)
{
    $session       = $configuration.UploadSession
    $directories   = Get-ChildItem -Path $localFolder -Recurse -Directory
    $remoteFolders = @($remoteFolder)
    $directories |% {
        $directory    = $_
        $relativePath = Get-RelativePath $localFolder $directory.FullName
        $remoteFolders += "$remoteFolder\$relativePath"
    }

    $null = Invoke-Command -Session $session -ScriptBlock {
        param($paths)
        $paths |% { $null = New-Item -ItemType Directory -Path $_ -Force }
    } -ArgumentList (,$remoteFolders)
}

function Copy-FolderToRemote($configuration, $localFolder, $remoteFolder)
{
    $session    = $configuration.UploadSession
    $localFiles = Get-ChildItem -Path $localFolder -Recurse -File
    if ($localFiles.Count -eq 0)
    {
        Write-Log "No files to upload in $localFolder"
        return
    }

    Write-Log "Uploading $localFolder to $remoteFolder"
    Add-RemoteFolders $configuration $localFolder $remoteFolder
    $remotePaths      = $localFiles |% { "$remoteFolder\$(Get-RelativePath $localFolder $_.FullName)" }
    $remoteFileHashes = Get-RemoteFileHashMap $configuration $remotePaths
    $uploadedFiles    = 0
    $skippedFiles     = 0

    $localFiles |% {
        $localFile    = $_
        $relativePath = Get-RelativePath $localFolder $localFile.FullName
        $remotePath   = "$remoteFolder\$relativePath"

        if (Test-IsLocalFileIgnored $configuration $localFile)
        {
            $skippedFiles++
            return
        }

        if (Test-IsRemoteFileProtected $configuration $remoteFileHashes $localFile $remotePath)
        {
            $skippedFiles++
            return
        }

        if (Test-IsFileUnchanged $localFile $remoteFileHashes $remotePath)
        {
            $skippedFiles++
            return
        }

        Send-ChunkedFile $configuration $session $localFile $remotePath
        $uploadedFiles++
    }

    Write-Log "Uploaded $uploadedFiles file(s) to $remoteFolder, skipped $skippedFiles"
}

function Invoke-UploadFolder($configuration)
{
    $skipUpload = $configuration.skipUpload
    if ($skipUpload)
    {
        Write-Log "skipUpload is set, running the scripts without an upload"
        return
    }

    $localBaseFolder  = $configuration.LocalBaseFolder
    $remoteBaseFolder = $configuration.remoteBaseFolder

    $configuration.localFolders |% {
        $folderName = $_
        Copy-FolderToRemote $configuration "$localBaseFolder\$folderName" "$remoteBaseFolder\$folderName"
    }

    $configuration.configurationFoldersToUploadToRemote |% {
        $folderName  = $_
        $localFolder = Get-ConfigurationFolderSource $configuration $folderName
        Copy-FolderToRemote $configuration $localFolder "$remoteBaseFolder\$folderName"
    }
}
