BeforeAll {
    $repositoryRoot = (Get-Item "$PSScriptRoot\..\..").FullName
    $installerRoot  = "$repositoryRoot\installer"
    $workRoot       = "$repositoryRoot\temporary_assets\installer-tests"
    $powerShellPath = (Get-Process -Id $PID).Path
    $expectedDatabaseEngineArguments = '/Q /ACTION=Install /FEATURES=SQLENGINE,FULLTEXT,IS,Conn,SDK /IACCEPTSQLSERVERLICENSETERMS'
    $expectedReportServerArguments   = '/quiet /ACTION=INSTALL /INSTANCENAME=SSRS /EDITION=Developer /IAcceptLicenseTerms'
    $expectedMethodOrder             = @('SetDatabaseConnection', 'CreateDatabase', 'SetVirtualDirectory', 'ReserveUrl', 'ReserveUrl')

    function Get-ScriptAst($scriptPath)
    {
        $tokens = $null
        $errors = $null
        $scriptAst = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
        return $scriptAst
    }

    function Get-ScriptFunctionText($function)
    {
        $scriptPath   = $function.ScriptPath
        $functionName = $function.FunctionName
        $scriptAst    = Get-ScriptAst $scriptPath
        $functionAst  = $scriptAst.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $functionName }, $true) | Select-Object -First 1
        return $functionAst.Extent.Text
    }

    function New-InstallCase($case)
    {
        $caseName    = $case.Name
        $caseRoot    = "$workRoot\$caseName"
        $mediaFolder = "$caseRoot\media"
        if (Test-Path $caseRoot)
        {
            Remove-Item -Path $caseRoot -Recurse -Force
        }
        $null = New-Item -ItemType Directory -Path $mediaFolder -Force
        Copy-Item -Path $case.ScriptSource -Destination "$caseRoot\install.ps1"
        $settings = $case.Settings
        $settings.mediaFolderPath = $mediaFolder
        $settings | ConvertTo-Json | Set-Content -Path "$caseRoot\settings.json" -Encoding ascii
        $installerPath = "$mediaFolder\$($settings.installerFileName)"
        Set-Content -Path $installerPath -Value $case.InstallerContent -Encoding ascii
        return $caseRoot
    }

    function Invoke-InstallCase($run)
    {
        $caseRoot           = $run.CaseRoot
        $powerShell         = $run.PowerShellPath
        $scriptPath         = "$caseRoot\install.ps1"
        $standardOutputPath = "$caseRoot\standard-output.txt"
        $standardErrorPath  = "$caseRoot\standard-error.txt"
        $process = Start-Process -FilePath $powerShell -ArgumentList @('-NoProfile', '-File', $scriptPath) -Wait -PassThru -RedirectStandardOutput $standardOutputPath -RedirectStandardError $standardErrorPath
        $standardOutput = Get-Content -Path $standardOutputPath -Raw
        $standardError  = Get-Content -Path $standardErrorPath -Raw
        $result = [pscustomobject]@{
            ExitCode       = $process.ExitCode
            StandardOutput = $standardOutput
            StandardError  = $standardError
            ArgumentsPath  = "$caseRoot\media\arguments.txt"
        }
        return $result
    }

    function New-ConfigurationModule($functionTexts)
    {
        $module = New-Module -ArgumentList (, $functionTexts) -ScriptBlock {
            param($functionTexts)
            $script:returnValue = 0
            $script:receivedMethodNames = @()
            function Invoke-CimMethod
            {
                param($InputObject, $MethodName, $Arguments)
                $script:receivedMethodNames = $script:receivedMethodNames + $MethodName
                return [pscustomobject]@{ ReturnValue = $script:returnValue }
            }
            $functionTexts |% {
                $functionText = $_
                . ([scriptblock]::Create($functionText))
            }
            Export-ModuleMember -Function 'Get-Configuration', 'Invoke-ConfigurationSettingMethod', 'Invoke-ReportServerConfiguration'
        }
        return $module
    }
}
Describe 'SQL Server install script' {
    It 'declares no parameter' {
        $scriptAst  = Get-ScriptAst "$installerRoot\sql-server\install.ps1"
        $paramBlock = $scriptAst.ParamBlock
        $paramBlock | Should -BeNullOrEmpty
    }

    It 'runs the unattended setup command line with the feature set section 6 records' {
        $case = [pscustomobject]@{
            Name             = 'sql-server-success'
            ScriptSource     = "$installerRoot\sql-server\install.ps1"
            Settings         = [pscustomobject]@{ mediaFolderPath = ''; installerFileName = 'setup.cmd' }
            InstallerContent = @('@echo off', 'echo %* > "%~dp0arguments.txt"', 'exit /b 0')
        }
        $caseRoot = New-InstallCase $case
        $run      = [pscustomobject]@{ CaseRoot = $caseRoot; PowerShellPath = $powerShellPath }
        $result   = Invoke-InstallCase $run
        $arguments = (Get-Content -Path $result.ArgumentsPath -Raw).Trim()
        $result.ExitCode | Should -Be 0
        $arguments | Should -Be $expectedDatabaseEngineArguments
    }

    It 'fails when the setup program exits with a non-zero exit code' {
        $case = [pscustomobject]@{
            Name             = 'sql-server-failure'
            ScriptSource     = "$installerRoot\sql-server\install.ps1"
            Settings         = [pscustomobject]@{ mediaFolderPath = ''; installerFileName = 'setup.cmd' }
            InstallerContent = @('@echo off', 'exit /b 3')
        }
        $caseRoot = New-InstallCase $case
        $run      = [pscustomobject]@{ CaseRoot = $caseRoot; PowerShellPath = $powerShellPath }
        $result   = Invoke-InstallCase $run
        $result.ExitCode | Should -Be 1
        $result.StandardError | Should -BeLike '*failed with exit code 3*'
    }
}

Describe 'Report server install script' {
    It 'declares no parameter' {
        $scriptAst  = Get-ScriptAst "$installerRoot\report-server\install.ps1"
        $paramBlock = $scriptAst.ParamBlock
        $paramBlock | Should -BeNullOrEmpty
    }

    It 'runs the unattended installer command line section 6 records' {
        $case = [pscustomobject]@{
            Name             = 'report-server-success'
            ScriptSource     = "$installerRoot\report-server\install.ps1"
            Settings         = [pscustomobject]@{ mediaFolderPath = ''; installerFileName = 'PowerBIReportServer.cmd'; instanceName = 'SSRS'; edition = 'Developer' }
            InstallerContent = @('@echo off', 'echo %* > "%~dp0arguments.txt"', 'exit /b 0')
        }
        $caseRoot = New-InstallCase $case
        $run      = [pscustomobject]@{ CaseRoot = $caseRoot; PowerShellPath = $powerShellPath }
        $result   = Invoke-InstallCase $run
        $arguments = (Get-Content -Path $result.ArgumentsPath -Raw).Trim()
        $result.ExitCode | Should -Be 0
        $arguments | Should -Be $expectedReportServerArguments
    }

    It 'fails when the bundle exits with a non-zero exit code' {
        $case = [pscustomobject]@{
            Name             = 'report-server-failure'
            ScriptSource     = "$installerRoot\report-server\install.ps1"
            Settings         = [pscustomobject]@{ mediaFolderPath = ''; installerFileName = 'PowerBIReportServer.cmd'; instanceName = 'SSRS'; edition = 'Developer' }
            InstallerContent = @('@echo off', 'exit /b 7')
        }
        $caseRoot = New-InstallCase $case
        $run      = [pscustomobject]@{ CaseRoot = $caseRoot; PowerShellPath = $powerShellPath }
        $result   = Invoke-InstallCase $run
        $result.ExitCode | Should -Be 1
        $result.StandardError | Should -BeLike '*failed with exit code 7*'
    }
}

Describe 'Report server configuration script' {
    It 'declares no parameter' {
        $scriptAst  = Get-ScriptAst "$installerRoot\report-server\configure.ps1"
        $paramBlock = $scriptAst.ParamBlock
        $paramBlock | Should -BeNullOrEmpty
    }

    It 'calls the configuration setting methods in the order section 6 records' {
        $configurePath = "$installerRoot\report-server\configure.ps1"
        $functionTexts = @('Write-Log', 'Get-Configuration', 'Invoke-ConfigurationSettingMethod', 'Invoke-ReportServerConfiguration') |% {
            $functionName = $_
            $function     = [pscustomobject]@{ ScriptPath = $configurePath; FunctionName = $functionName }
            Get-ScriptFunctionText $function
        }
        $module = New-ConfigurationModule $functionTexts
        Push-Location "$installerRoot\report-server"
        $configuration = & $module { Get-Configuration }
        Pop-Location
        & $module { param($configuration) Invoke-ReportServerConfiguration $configuration } $configuration
        $receivedMethodNames = & $module { $script:receivedMethodNames }
        $expectedOrderText   = $expectedMethodOrder -join ','
        $receivedOrderText   = $receivedMethodNames -join ','
        $configuration.instanceName | Should -Be 'SSRS'
        $receivedOrderText | Should -Be $expectedOrderText
    }

    It 'fails when a configuration setting method returns a non-zero HRESULT' {
        $configurePath = "$installerRoot\report-server\configure.ps1"
        $functionTexts = @('Write-Log', 'Invoke-ConfigurationSettingMethod') |% {
            $functionName = $_
            $function     = [pscustomobject]@{ ScriptPath = $configurePath; FunctionName = $functionName }
            Get-ScriptFunctionText $function
        }
        $module     = New-ConfigurationModule $functionTexts
        $methodCall = [pscustomobject]@{ MethodName = 'CreateDatabase'; Arguments = @{} }
        & $module { $script:returnValue = 1053 }
        $failingCall = { & $module { param($methodCall) Invoke-ConfigurationSettingMethod $null $methodCall } $methodCall }
        $failingCall | Should -Throw -ExpectedMessage '*failed with HRESULT 1053*'
        $receivedMethodNames = & $module { $script:receivedMethodNames }
        $receivedOrderText   = $receivedMethodNames -join ','
        $receivedOrderText | Should -Be 'CreateDatabase'
        & $module { $script:returnValue = 0 }
        & $module { param($methodCall) Invoke-ConfigurationSettingMethod $null $methodCall } $methodCall
        $receivedMethodNames = & $module { $script:receivedMethodNames }
        $receivedOrderText   = $receivedMethodNames -join ','
        $receivedOrderText | Should -Be 'CreateDatabase,CreateDatabase'
    }
}

AfterAll {
    if (Test-Path $workRoot)
    {
        Remove-Item -Path $workRoot -Recurse -Force
    }
}
