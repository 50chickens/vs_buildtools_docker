$ErrorActionPreference = 'Stop'
$VerbosePreference     = 'SilentlyContinue'
Set-Location $PSScriptRoot

function Write-Log($message)
{
    Write-Host "[$([DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss'))] $message"
}

function Get-Configuration
{
    $dockerHostFolder  = (Get-Item "..").FullName
    $cachedAssetsFolder = "$dockerHostFolder\cached_assets"
    $dockerFolder      = "$dockerHostFolder\docker"
    $dataRoot          = "$dockerHostFolder\docker-data"
    $dockerArchive     = Get-ChildItem -Path $cachedAssetsFolder -Filter 'docker-*.zip' | Select-Object -First 1

    $configuration = [pscustomobject]@{
        DockerHostFolder  = $dockerHostFolder
        DockerArchivePath = $dockerArchive.FullName
        DockerFolder      = $dockerFolder
        DockerdPath       = "$dockerFolder\dockerd.exe"
        DockerPath        = "$dockerFolder\docker.exe"
        DataRoot          = $dataRoot
        ServiceName       = 'docker'
    }
    return $configuration
}

function Test-ShouldExpandArchive($configuration)
{
    $dockerdPath = $configuration.DockerdPath
    if (Test-Path -Path $dockerdPath)
    {
        Write-Log "$dockerdPath is already present"
        return $false
    }
    return $true
}

function Expand-DockerArchive($configuration)
{
    if (!(Test-ShouldExpandArchive $configuration))
    {
        return
    }

    $dockerArchivePath = $configuration.DockerArchivePath
    $dockerHostFolder  = $configuration.DockerHostFolder
    Write-Log "Expanding $dockerArchivePath into $dockerHostFolder"
    Expand-Archive -Path $dockerArchivePath -DestinationPath $dockerHostFolder -Force
}

function Test-ShouldRegisterService($configuration)
{
    $serviceName     = $configuration.ServiceName
    $existingService = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($null -ne $existingService)
    {
        Write-Log "Service $serviceName already exists"
        return $false
    }
    return $true
}

function Install-DockerService($configuration)
{
    $dockerdPath = $configuration.DockerdPath
    $dataRoot    = $configuration.DataRoot
    $serviceName = $configuration.ServiceName
    $null = New-Item -ItemType Directory -Path $dataRoot -Force

    if (Test-ShouldRegisterService $configuration)
    {
        Write-Log "Registering the $serviceName service from $dockerdPath with data root $dataRoot"
        & $dockerdPath --register-service --data-root $dataRoot
        if ($LASTEXITCODE -ne 0)
        {
            throw "dockerd --register-service exited with code $LASTEXITCODE"
        }
    }

    Start-Service -Name $serviceName
    Write-Log "Service $serviceName started"
}

function Add-DockerToPath($configuration)
{
    $dockerFolder = $configuration.DockerFolder
    $machinePath  = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $pathEntries  = $machinePath -split ';'
    if ($pathEntries -contains $dockerFolder)
    {
        Write-Log "$dockerFolder is already on the machine path"
        return
    }

    Write-Log "Adding $dockerFolder to the machine path"
    $newMachinePath = "$machinePath;$dockerFolder"
    [Environment]::SetEnvironmentVariable('Path', $newMachinePath, 'Machine')
}

function Test-DockerEngine($configuration)
{
    $dockerPath = $configuration.DockerPath
    Write-Log "Reading the engine version from $dockerPath"
    $engineVersion = & $dockerPath version --format '{{.Server.Version}}'
    if ($LASTEXITCODE -ne 0)
    {
        throw "docker version exited with code $LASTEXITCODE"
    }
    Write-Log "Docker engine version $engineVersion"
}

$configuration = Get-Configuration
Expand-DockerArchive $configuration
Install-DockerService $configuration
Add-DockerToPath $configuration
Test-DockerEngine $configuration
