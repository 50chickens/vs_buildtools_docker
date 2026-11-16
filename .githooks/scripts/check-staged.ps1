$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

function Write-Log($message)
{
    Write-Host $message
}

function Get-Configuration
{
    $scriptRoot = (Get-Item '.').FullName
    $repoRoot = (Get-Item '..\..').FullName
    $configRoot = "$scriptRoot\..\config"
    $configuration = [pscustomobject]@{}
    $configuration | Add-Member -NotePropertyName 'ScriptRoot' -NotePropertyValue $scriptRoot -Force
    $configuration | Add-Member -NotePropertyName 'RepoRoot' -NotePropertyValue $repoRoot -Force
    $configuration | Add-Member -NotePropertyName 'PatternsPath' -NotePropertyValue "$configRoot\patterns.json" -Force
    $configuration | Add-Member -NotePropertyName 'ChecksPath' -NotePropertyValue "$configRoot\checks.json" -Force
    $configuration | Add-Member -NotePropertyName 'CodeRulesPath' -NotePropertyValue "$configRoot\code-rules.json" -Force
    $configuration | Add-Member -NotePropertyName 'ExemptionsPath' -NotePropertyValue "$configRoot\exemptions.json" -Force
    return $configuration
}

function Get-FileName($path)
{
    switch -Regex ($path)
    {
        '([^\\/]+)$' { return $Matches[1] }
        default      { return $path }
    }
}

function Get-Language($fileNameCheck)
{
    $fileName = $fileNameCheck.FileName
    $languages = $fileNameCheck.Languages
    $language = $null
    $languages.PSObject.Properties |% {
        $languageEntry = $_
        $globs = @($languageEntry.Value)
        $matched = @($globs |? { $fileName -like $_ })
        if ([string]::IsNullOrEmpty($language) -and $matched.Count -gt 0)
        {
            $language = $languageEntry.Name
        }
    }
    return $language
}

function Get-PatternAllowCount($pattern, $text)
{
    $allowList = @($pattern.allow |? { ![string]::IsNullOrEmpty($_) })
    $allowedCount = @($allowList |? { $text -match $_ }).Count
    return $allowedCount
}

function Get-EnclosingFunctionName($lines)
{
    $names = @()
    $pendingName = $null
    $depth = 0
    $openFunctions = @()

    $lines |% {
        $text = $_

        if ($text -match '^\s*function\s+([A-Za-z0-9_-]+)')
        {
            $pendingName = $Matches[1]
        }

        $opened = ([regex]::Matches($text, '\{')).Count
        $closed = ([regex]::Matches($text, '\}')).Count

        if ($null -ne $pendingName -and $opened -gt 0)
        {
            $openFunctions += [pscustomobject]@{ Name = $pendingName; Depth = $depth }
            $pendingName = $null
        }

        $current = $null
        if ($openFunctions.Count -gt 0)
        {
            $current = $openFunctions[-1].Name
        }
        $names += $current

        $depth = $depth + $opened - $closed
        while ($openFunctions.Count -gt 0 -and $depth -le $openFunctions[-1].Depth)
        {
            $openFunctions = @($openFunctions | Select-Object -SkipLast 1)
        }
    }

    return $names
}

function Get-CodeViolation($fileCheck)
{
    $path = $fileCheck.Path
    $lines = $fileCheck.Lines
    $rules = $fileCheck.Rules
    $findings = @()
    $lineNo = 0
    $enclosingFunctions = Get-EnclosingFunctionName $lines

    $lines |% {
        $text = $_
        $enclosingFunction = $null
        if ($lineNo -lt $enclosingFunctions.Count)
        {
            $enclosingFunction = $enclosingFunctions[$lineNo]
        }
        $lineNo = $lineNo + 1

        $rules |% {
            $rule = $_
            $scoped = !([string]::IsNullOrEmpty($rule.scopeName))
            $insideScope = $scoped -and $enclosingFunction -eq $rule.scopeName
            if (!$insideScope -and ($text -match $rule.regex))
            {
                $matchedText = [regex]::Match($text, $rule.regex, 'IgnoreCase').Value
                $finding = [pscustomobject]@{
                    File = $path
                    Line = $lineNo
                    Pattern = $rule.name
                    Match = $matchedText
                }
                $findings += $finding
            }
        }
    }

    return $findings
}

function Add-RuntimeConfiguration($configuration)
{
    $patterns = @((Get-Content -Path $configuration.PatternsPath -Raw | ConvertFrom-Json).patterns)
    $checks = Get-Content -Path $configuration.ChecksPath -Raw | ConvertFrom-Json
    $codeRules = Get-Content -Path $configuration.CodeRulesPath -Raw | ConvertFrom-Json
    $exemptionFile = Get-Content -Path $configuration.ExemptionsPath -Raw | ConvertFrom-Json
    $exemptions = @($exemptionFile.exemptions)
    $include = @($checks.include)
    $exclude = @($checks.exclude)

    $gitDir = git -C $configuration.RepoRoot rev-parse --absolute-git-dir
    if ($LASTEXITCODE -ne 0)
    {
        throw "git rev-parse --absolute-git-dir failed (exit $LASTEXITCODE)"
    }
    $messagePath = "$gitDir\COMMIT_EDITMSG"

    $stagedFiles = @(git -C $configuration.RepoRoot diff --cached --name-only --diff-filter=ACM)
    if ($LASTEXITCODE -ne 0)
    {
        throw "git diff --cached failed (exit $LASTEXITCODE)"
    }

    $targets = @($stagedFiles |? {
        $stagedFile = $_
        $fileName = Get-FileName $stagedFile
        $includedCount = @($include |? { $fileName -like $_ }).Count
        $excludedCount = @($exclude |? { $fileName -like $_ }).Count
        $includedCount -gt 0 -and $excludedCount -eq 0
    })

    $configuration | Add-Member -NotePropertyName 'Patterns' -NotePropertyValue $patterns -Force
    $configuration | Add-Member -NotePropertyName 'Languages' -NotePropertyValue $codeRules.languages -Force
    $configuration | Add-Member -NotePropertyName 'CodeRules' -NotePropertyValue $codeRules.rules -Force
    $configuration | Add-Member -NotePropertyName 'Targets' -NotePropertyValue $targets -Force
    $configuration | Add-Member -NotePropertyName 'Exemptions' -NotePropertyValue $exemptions -Force
    $configuration | Add-Member -NotePropertyName 'MessagePath' -NotePropertyValue $messagePath -Force
    $exemptionTags = Get-ExemptionTag $configuration
    $configuration | Add-Member -NotePropertyName 'ExemptionTags' -NotePropertyValue $exemptionTags -Force
    return $configuration
}

function Invoke-PreflightCheck($configuration)
{
    $ruleFiles = @($configuration.PatternsPath, $configuration.ChecksPath, $configuration.CodeRulesPath, $configuration.ExemptionsPath)
    $ruleFiles |% {
        $ruleFile = $_
        if (!(Test-Path $ruleFile))
        {
            throw "Rule file not found: $ruleFile"
        }
    }
}

function Get-StagedLine($stagedFileCheck)
{
    $repoRoot = $stagedFileCheck.RepoRoot
    $path = $stagedFileCheck.Path
    $lines = @(git -C $repoRoot show ":$path")
    if ($LASTEXITCODE -ne 0)
    {
        throw "git show :$path failed (exit $LASTEXITCODE)"
    }
    return $lines
}

function Get-ContentFinding($configuration)
{
    $patterns = $configuration.Patterns
    $findings = @()

    $configuration.Targets |% {
        $path = $_
        $stagedFileCheck = [pscustomobject]@{
            RepoRoot = $configuration.RepoRoot
            Path = $path
        }
        $lines = Get-StagedLine $stagedFileCheck
        $lineNo = 0

        $lines |% {
            $lineNo = $lineNo + 1
            $text = $_
            $patterns |% {
                $pattern = $_
                if ($text -match $pattern.regex)
                {
                    $allowedCount = Get-PatternAllowCount $pattern $text
                    if ($allowedCount -eq 0)
                    {
                        $matchedText = [regex]::Match($text, $pattern.regex, 'IgnoreCase').Value
                        $finding = [pscustomobject]@{
                            File = $path
                            Line = $lineNo
                            Pattern = $pattern.name
                            Match = $matchedText
                        }
                        $findings += $finding
                    }
                }
            }
        }
    }

    return $findings
}

function Get-CodeFinding($configuration)
{
    $findings = @()

    $configuration.Targets |% {
        $path = $_
        $fileName = Get-FileName $path
        $fileNameCheck = [pscustomobject]@{
            FileName = $fileName
            Languages = $configuration.Languages
        }
        $language = Get-Language $fileNameCheck

        if ($language)
        {
            $stagedFileCheck = [pscustomobject]@{
                RepoRoot = $configuration.RepoRoot
                Path = $path
            }
            $lines = Get-StagedLine $stagedFileCheck
            $rules = @($configuration.CodeRules |? { $_.appliesTo -contains $language })
            $fileCheck = [pscustomobject]@{
                Path = $path
                Lines = $lines
                Rules = $rules
            }
            $findings += Get-CodeViolation $fileCheck
        }
    }

    return $findings
}

function Get-ExemptionTag($configuration)
{
    $messagePath = $configuration.MessagePath
    $tags = @()
    if (Test-Path $messagePath)
    {
        $message = Get-Content -Path $messagePath -Raw
        $tags = @([regex]::Matches($message, '\[exemptions\|[^\]]+\]') |% {
            $tagText = $_.Value
            Get-ExemptionTagDetail $tagText
        })
    }
    return $tags
}

function Get-ExemptionTagDetail($tagText)
{
    $body = $tagText.Trim('[', ']')
    $fields = @($body -split '\|')
    $fileSpec = $fields | Select-Object -Skip 1 -First 1
    $lineSpec = $fields | Select-Object -Last 1
    $pattern = $null
    if ($fields.Count -eq 4)
    {
        $pattern = $fields | Select-Object -Skip 2 -First 1
    }
    $lineNumbers = Get-LineNumber $lineSpec
    $detail = [pscustomobject]@{
        FileSpec = $fileSpec
        Pattern = $pattern
        LineNumbers = $lineNumbers
    }
    return $detail
}

function Get-LineNumber($lineSpec)
{
    $lineNumbers = @($lineSpec -split ',' |% {
        $token = $_
        $bounds = @($token -split '-')
        if ($bounds.Count -eq 2)
        {
            $from = [int]($bounds | Select-Object -First 1)
            $to = [int]($bounds | Select-Object -Last 1)
            $from..$to
        }
        else
        {
            [int]$token
        }
    })
    return $lineNumbers
}

function Invoke-CollectFindings($configuration)
{
    $findings = @()
    $findings += Get-ContentFinding $configuration
    $findings += Get-CodeFinding $configuration
    $configuration | Add-Member -NotePropertyName 'Findings' -NotePropertyValue $findings -Force
    return $configuration
}

function Invoke-UpdateExemptions($configuration)
{
    $tags = $configuration.ExemptionTags
    if ($tags.Count -eq 0)
    {
        return $configuration
    }

    $findings = $configuration.Findings
    $exemptions = $configuration.Exemptions
    $candidates = @($tags |% {
        $tag = $_
        $findings |% {
            $finding = $_
            $isFile = $finding.File -like $tag.FileSpec
            $isLine = $tag.LineNumbers -contains $finding.Line
            $isPattern = [string]::IsNullOrEmpty($tag.Pattern) -or $tag.Pattern -eq $finding.Pattern
            if ($isFile -and $isLine -and $isPattern)
            {
                [pscustomobject]@{
                    file = $finding.File
                    line = $finding.Line
                    pattern = $finding.Pattern
                }
            }
        }
    })

    $newExemptions = @($candidates |? {
        $candidate = $_
        $existing = @($exemptions |? {
            $exemption = $_
            $exemption.file -eq $candidate.file -and $exemption.line -eq $candidate.line -and $exemption.pattern -eq $candidate.pattern
        })
        $existing.Count -eq 0
    })
    if ($newExemptions.Count -eq 0)
    {
        return $configuration
    }

    $exemptionFile = [pscustomobject]@{
        exemptions = @($exemptions + $newExemptions)
    }
    $exemptionFile | ConvertTo-Json -Depth 3 | Set-Content -Path $configuration.ExemptionsPath
    $updated = $exemptionFile.exemptions
    $configuration | Add-Member -NotePropertyName 'Exemptions' -NotePropertyValue $updated -Force
    return $configuration
}

function Remove-ExemptedFinding($configuration)
{
    $exemptions = $configuration.Exemptions
    $findings = @($configuration.Findings |? {
        $finding = $_
        $exempted = @($exemptions |? {
            $exemption = $_
            $isFile = $exemption.file -eq $finding.File
            $isLine = $exemption.line -eq $finding.Line
            $isPattern = [string]::IsNullOrEmpty($exemption.pattern) -or $exemption.pattern -eq $finding.Pattern
            $isFile -and $isLine -and $isPattern
        })
        $exempted.Count -eq 0
    })
    $configuration | Add-Member -NotePropertyName 'Findings' -NotePropertyValue $findings -Force
    return $configuration
}

function Invoke-CheckEnabled($configuration)
{
    $findings = $configuration.Findings
    if ($findings.Count -eq 0)
    {
        exit 0
    }

    Write-Log "Commit blocked: $($findings.Count) violation(s) in staged changes."
    $findings |% {
        $finding = $_
        Write-Log "  $($finding.File):$($finding.Line)  $($finding.Pattern)  $($finding.Match)"
    }
    Write-Log "Credential and PII patterns: $($configuration.PatternsPath)"
    Write-Log "Code rules: $($configuration.CodeRulesPath)"
    Write-Log "Exemptions: $($configuration.ExemptionsPath)"
    exit 1
}

$configuration = Get-Configuration
$configuration = Add-RuntimeConfiguration $configuration
Invoke-PreflightCheck $configuration
$configuration = Invoke-CollectFindings $configuration
$configuration = Invoke-UpdateExemptions $configuration
$configuration = Remove-ExemptedFinding $configuration
Invoke-CheckEnabled $configuration
