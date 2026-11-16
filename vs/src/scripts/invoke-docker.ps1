$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

function Write-Log($message) {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] $message"
}

function Get-Configuration($ConfigurationFolder) {
    $configFile = Get-ChildItem -Path $ConfigurationFolder -Filter '*.json' | Select-Object -First 1
    return Get-Content $configFile.FullName -Raw | ConvertFrom-Json
}

function Invoke-PreflightCheck($configuration) {
    Write-Log "Running preflight checks..."
    docker info 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Docker is not running or not available."
        exit 1
    }
}

function Invoke-RemoveExistingImage($configuration) {
    Write-Log "Removing existing image if present..."
    $imageName = $configuration.imageName
    $imageTag = $configuration.imageTag
    docker rmi "${imageName}:${imageTag}" 2>&1 | Out-Null
}

function Invoke-DockerBuild($configuration) {
    Write-Log "Building docker image..."
    $imageName = $configuration.imageName
    $imageTag = $configuration.imageTag
    $dockerfilePath = Join-Path $PSScriptRoot "docker\Dockerfile"
    $contextPath = Join-Path $PSScriptRoot "docker\context"

    docker build -t "${imageName}:${imageTag}" -f $dockerfilePath $contextPath

    if ($LASTEXITCODE -ne 0) {
        Write-Error "Docker build failed with exit code $LASTEXITCODE"
        exit $LASTEXITCODE
    }
    Write-Log "Docker image ${imageName}:${imageTag} built successfully."
}

$configurationFolder = Join-Path $PSScriptRoot "configs"

$configuration = Get-Configuration -ConfigurationFolder $configurationFolder
Invoke-PreflightCheck -configuration $configuration
Invoke-RemoveExistingImage -configuration $configuration
Invoke-DockerBuild -configuration $configuration
