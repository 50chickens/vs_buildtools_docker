$ErrorActionPreference = 'Stop'
$VerbosePreference     = 'SilentlyContinue'
Set-Location $PSScriptRoot

function Write-Log($message)
{
    Write-Host "[$([DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss'))] $message"
}

function Get-Configuration
{
    $scriptFolder          = (Get-Item ".").FullName
    $settingsPath          = "$scriptFolder\settings.json"
    $settings              = Get-Content -Path $settingsPath -Raw | ConvertFrom-Json
    $secretsStore          = $env:SECRETS_STORE
    $credentialName        = $settings.credentialFileName
    $localBaseFolder       = (Get-Item "$scriptFolder\$($settings.localBaseFolder)").FullName
    $sealedCredentialPath  = "$secretsStore\$credentialName.user.dpapi"
    $credentialPlaceholder = 'sealed'

    $configuration = $settings
    $configuration | Add-Member -NotePropertyName 'LocalBaseFolder'       -NotePropertyValue $localBaseFolder       -Force
    $configuration | Add-Member -NotePropertyName 'SealedCredentialPath'  -NotePropertyValue $sealedCredentialPath  -Force
    $configuration | Add-Member -NotePropertyName 'CredentialPlaceholder' -NotePropertyValue $credentialPlaceholder -Force
    return $configuration
}

function Invoke-PreflightCheck($configuration)
{
    $valuesToCheck = @('remoteHost', 'remoteBaseFolder')
    $valuesToCheck |% {
        $valueName = $_
        $value     = $configuration.$valueName
        if ([string]::IsNullOrEmpty($value))
        {
            throw "$valueName is required in settings.json."
        }
    }

    $localFolders = $configuration.localFolders
    if ($localFolders.Count -eq 0)
    {
        throw "localFolders is empty in settings.json, so the upload would copy nothing."
    }
}

function Connect-UploadSession($configuration)
{
    $session = New-RemoteSession $configuration
    $configuration | Add-Member -NotePropertyName 'UploadSession' -NotePropertyValue $session -Force
    return $configuration
}

function Disconnect-UploadSession($configuration)
{
    $session = $configuration.UploadSession
    Write-Log "Closing upload session $($session.Id)"
    Remove-PSSession -Session $session
}

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
    if ($useSsl -and $skipCertificateCheck)
    {
        $sessionOption = New-PSSessionOption -SkipCACheck -SkipCNCheck -SkipRevocationCheck
        return $sessionOption
    }

    $sessionOption = New-PSSessionOption
    return $sessionOption
}

function New-RemoteSession($configuration)
{
    $remoteHost    = $configuration.remoteHost
    $remotePort    = $configuration.remotePort
    $useSsl        = $configuration.useSsl
    $credential    = Get-RemoteCredential $configuration
    $sessionOption = Get-SessionOption $configuration
    Write-Log "Opening a WinRM session to $remoteHost port $remotePort as $($credential.UserName)"

    $sessionParameters = @{
        ComputerName  = $remoteHost
        Port          = $remotePort
        UseSSL        = $useSsl
        Credential    = $credential
        SessionOption = $sessionOption
    }
    $session = New-PSSession @sessionParameters
    Write-Log "Session $($session.Id) established with $remoteHost"
    return $session
}

function Get-RelativePath($baseFolder, $fullPath)
{
    $relativePath = $fullPath.Substring($baseFolder.Length).TrimStart('\')
    return $relativePath
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

function Get-RemoteFileHashMap($configuration, $remotePaths)
{
    $session    = $configuration.UploadSession
    $fileHashes = Invoke-Command -Session $session -ScriptBlock {
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
    } -ArgumentList (,$remotePaths)
    return $fileHashes
}

function Invoke-UploadFolder($configuration)
{
    $session          = $configuration.UploadSession
    $localBaseFolder  = $configuration.LocalBaseFolder
    $remoteBaseFolder = $configuration.remoteBaseFolder
    $localFolders     = $configuration.localFolders

    $localFolders |% {
        $folderName   = $_
        $localFolder  = "$localBaseFolder\$folderName"
        $remoteFolder = "$remoteBaseFolder\$folderName"
        $localFiles   = Get-ChildItem -Path $localFolder -Recurse -File
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
            $localHash    = (Get-FileHash -Path $localFile.FullName -Algorithm MD5).Hash
            if ($remoteFileHashes[$remotePath] -eq $localHash)
            {
                $skippedFiles++
                return
            }

            Copy-Item -Path $localFile.FullName -Destination $remotePath -ToSession $session -Force
            $uploadedFiles++
        }

        Write-Log "Uploaded $uploadedFiles file(s) to $remoteFolder, skipped $skippedFiles unchanged"
    }
}

function Invoke-RemoteScript($configuration)
{
    $remoteBaseFolder = $configuration.remoteBaseFolder
    $remoteScripts    = $configuration.remoteScripts

    $remoteScripts |? { $_.enabled } |% {
        $remoteScript     = $_
        $remoteScriptPath = "$remoteBaseFolder\$($remoteScript.filePath)"
        Invoke-RemoteScriptFile $configuration $remoteScriptPath
    }
}

function Invoke-RemoteScriptFile($configuration, $remoteScriptPath)
{
    $session = New-RemoteSession $configuration
    Write-Log "Running $remoteScriptPath"

    $null = Invoke-Command -Session $session -ScriptBlock {
        param($path)
        & $path
    } -ArgumentList $remoteScriptPath

    Write-Log "Finished $remoteScriptPath"
    Wait-RemoteHostAvailable $configuration
    Remove-PSSession -Session $session
}

function Test-RemoteHostAvailable($configuration)
{
    $remoteHost  = $configuration.remoteHost
    $remotePort  = $configuration.remotePort
    $isAvailable = Test-NetConnection -ComputerName $remoteHost -Port $remotePort -InformationLevel Quiet
    return $isAvailable
}

function Wait-RemoteHostAvailable($configuration)
{
    $remoteHost           = $configuration.remoteHost
    $remotePort           = $configuration.remotePort
    $retryIntervalSeconds = $configuration.retryIntervalSeconds
    $timeoutSeconds       = $configuration.timeoutSeconds
    $deadline             = (Get-Date).AddSeconds($timeoutSeconds)

    Start-Sleep -Seconds $retryIntervalSeconds
    $hostIsAvailable = Test-RemoteHostAvailable $configuration
    if (!$hostIsAvailable)
    {
        Write-Log "Waiting up to $timeoutSeconds seconds for $remoteHost port $remotePort"
    }

    while (!$hostIsAvailable)
    {
        if ((Get-Date) -gt $deadline)
        {
            throw "$remoteHost port $remotePort did not answer within $timeoutSeconds seconds."
        }
        Start-Sleep -Seconds $retryIntervalSeconds
        $hostIsAvailable = Test-RemoteHostAvailable $configuration
    }
}

$configuration = Get-Configuration
Invoke-PreflightCheck $configuration
$configuration = Connect-UploadSession $configuration
Invoke-UploadFolder $configuration
Disconnect-UploadSession $configuration
Invoke-RemoteScript $configuration
