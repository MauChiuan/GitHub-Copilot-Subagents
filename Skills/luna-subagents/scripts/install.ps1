#Requires -Version 7.0

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter()]
    [ValidateSet('Install', 'Verify')]
    [string]$Action = 'Install',

    [Parameter()]
    [string]$CopilotHome
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not [OperatingSystem]::IsWindows()) {
    throw 'PLATFORM_UNSUPPORTED: luna-subagents installation is supported only on Windows.'
}

$skillName = 'luna-subagents'
$agentFileName = 'luna-subagents-executor.agent.md'
$beginMarker = '<!-- BEGIN luna-subagents managed section -->'
$endMarker = '<!-- END luna-subagents managed section -->'
$managedHeading = '## Luna subagent 委派'
$canonicalRelativePaths = @(
    'SKILL.md',
    'assets/global-copilot-instructions-section.md',
    'assets/agents/luna-subagents-executor.agent.md',
    'scripts/install.ps1'
)
$legacyPackageRelativePaths = @(
    'scripts/resolve-quota-tier.ps1',
    'assets/agents/luna-subagents-executor.toml',
    'assets/agents/luna-subagents-executor-fast.toml',
    'assets/agents/luna-subagents-executor-standard.toml'
)
$legacyAgentFileNames = @(
    'luna-subagents-executor.toml',
    'luna-subagents-executor-fast.toml',
    'luna-subagents-executor-standard.toml'
)

if ($PSBoundParameters.ContainsKey('CopilotHome') -and [string]::IsNullOrWhiteSpace($CopilotHome)) {
    throw 'COPILOT_HOME_UNRESOLVED: -CopilotHome must not be empty or whitespace.'
}

function Get-NormalizedPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $fullPath = [IO.Path]::GetFullPath($Path)
    $pathRoot = [IO.Path]::GetPathRoot($fullPath)
    if ($fullPath -eq $pathRoot) {
        return $fullPath
    }

    return $fullPath.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
}

function Join-PortablePath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    $result = $Root
    foreach ($segment in [regex]::Split($RelativePath, '[\\/]')) {
        if (-not [string]::IsNullOrEmpty($segment)) {
            $result = Join-Path $result $segment
        }
    }
    return $result
}

function Test-SamePath {
    param(
        [Parameter(Mandatory = $true)][string]$First,
        [Parameter(Mandatory = $true)][string]$Second
    )

    return [string]::Equals(
        (Get-NormalizedPath -Path $First),
        (Get-NormalizedPath -Path $Second),
        [StringComparison]::OrdinalIgnoreCase
    )
}

function Resolve-CopilotHome {
    param([Parameter()][string]$RequestedPath)

    if (-not [string]::IsNullOrWhiteSpace($RequestedPath)) {
        return Get-NormalizedPath -Path $RequestedPath
    }
    if (-not [string]::IsNullOrWhiteSpace($env:COPILOT_HOME)) {
        return Get-NormalizedPath -Path $env:COPILOT_HOME
    }

    $userProfile = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
    if ([string]::IsNullOrWhiteSpace($userProfile)) {
        throw 'COPILOT_HOME_UNRESOLVED: Provide -CopilotHome or set COPILOT_HOME.'
    }
    return Get-NormalizedPath -Path (Join-Path $userProfile '.copilot')
}

function Test-ByteOrderMark {
    param([Parameter(Mandatory = $true)][string]$Path)

    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 3 -and
        $bytes[0] -eq 0xEF -and
        $bytes[1] -eq 0xBB -and
        $bytes[2] -eq 0xBF) {
        return $true
    }
    if ($bytes.Length -ge 2 -and
        (($bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) -or
        ($bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF))) {
        return $true
    }
    return $false
}

function Test-ReparsePoint {
    param([Parameter(Mandatory = $true)][string]$Path)

    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if ($null -eq $item) {
        return $false
    }
    return ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
}

function Assert-SafeManagedPaths {
    param(
        [Parameter(Mandatory = $true)][string]$TargetHome,
        [Parameter(Mandatory = $true)][string]$ErrorPrefix
    )

    $normalizedHome = Get-NormalizedPath -Path $TargetHome
    $pathRoot = [IO.Path]::GetPathRoot($normalizedHome)
    if ([string]::IsNullOrWhiteSpace($pathRoot)) {
        throw "${ErrorPrefix}: Copilot home path has no filesystem root: $normalizedHome"
    }

    $currentPath = $pathRoot
    if (Test-ReparsePoint -Path $currentPath) {
        throw "${ErrorPrefix}: Copilot home path must not contain a symbolic link or reparse point: $currentPath"
    }

    $relativeHome = $normalizedHome.Substring($pathRoot.Length)
    foreach ($segment in [regex]::Split($relativeHome, '[\\/]')) {
        if ([string]::IsNullOrWhiteSpace($segment)) {
            continue
        }
        $currentPath = Join-Path $currentPath $segment
        $item = Get-Item -LiteralPath $currentPath -Force -ErrorAction SilentlyContinue
        if ($null -eq $item) {
            break
        }
        if (Test-ReparsePoint -Path $currentPath) {
            throw "${ErrorPrefix}: Copilot home path must not contain a symbolic link or reparse point: $currentPath"
        }
    }

    $skillsRoot = Join-Path $TargetHome 'skills'
    $targetSkillRoot = Join-PortablePath -Root $TargetHome -RelativePath 'skills/luna-subagents'
    $agentsRoot = Join-Path $TargetHome 'agents'
    $targetAgentPath = Join-Path $agentsRoot $agentFileName
    $instructionsPath = Join-Path $TargetHome 'copilot-instructions.md'

    foreach ($managedPath in @(
        $skillsRoot,
        $targetSkillRoot,
        $agentsRoot,
        $targetAgentPath,
        $instructionsPath
    )) {
        if (Test-ReparsePoint -Path $managedPath) {
            throw "${ErrorPrefix}: managed path must not be a symbolic link or reparse point: $managedPath"
        }
    }

    if (Test-Path -LiteralPath $targetSkillRoot -PathType Container) {
        foreach ($item in Get-ChildItem -LiteralPath $targetSkillRoot -Recurse -Force) {
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "${ErrorPrefix}: installed skill must not contain symbolic links or reparse points: $($item.FullName)"
            }
        }
    }
}

function Convert-ToLf {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)

    return $Text.Replace("`r`n", "`n").Replace("`r", "`n")
}

function Get-YamlFrontmatter {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory = $true)][string]$ErrorMessage
    )

    $normalized = Convert-ToLf -Text $Text
    $match = [regex]::Match(
        $normalized,
        '\A---\n(?<frontmatter>.*?)\n---(?:\n|\z)',
        [Text.RegularExpressions.RegexOptions]::Singleline
    )
    if (-not $match.Success) {
        throw $ErrorMessage
    }
    return $match.Groups['frontmatter'].Value
}

function Convert-NewlineStyle {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory = $true)][string]$Newline
    )

    return (Convert-ToLf -Text $Text).Replace("`n", $Newline)
}

function Get-NewlineStyle {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)

    $match = [regex]::Match($Text, "`r`n|`n")
    if ($match.Success) {
        return $match.Value
    }
    return [Environment]::NewLine
}

function Get-CanonicalManagedBlock {
    param([Parameter(Mandatory = $true)][string]$AssetPath)

    if (Test-ByteOrderMark -Path $AssetPath) {
        throw 'PACKAGE_INSTRUCTIONS_INVALID: canonical managed section must be UTF-8 without a byte-order mark.'
    }

    $normalized = (Convert-ToLf -Text ([IO.File]::ReadAllText($AssetPath))).TrimEnd([char]10)
    $beginTokenCount = ([regex]::Matches($normalized, [regex]::Escape($beginMarker))).Count
    $endTokenCount = ([regex]::Matches($normalized, [regex]::Escape($endMarker))).Count
    $beginLineMatches = @([regex]::Matches(
        $normalized,
        '(?m)^[ \t]*' + [regex]::Escape($beginMarker) + '[ \t]*$'
    ))
    $endLineMatches = @([regex]::Matches(
        $normalized,
        '(?m)^[ \t]*' + [regex]::Escape($endMarker) + '[ \t]*$'
    ))
    $headingMatches = @([regex]::Matches(
        $normalized,
        '(?m)^##(?!#)[ \t]+Luna subagent 委派[ \t]*$'
    ))

    if ($beginTokenCount -ne 1 -or
        $endTokenCount -ne 1 -or
        $beginLineMatches.Count -ne 1 -or
        $endLineMatches.Count -ne 1 -or
        $beginLineMatches[0].Index -ne 0 -or
        ($endLineMatches[0].Index + $endLineMatches[0].Length) -ne $normalized.Length -or
        $beginLineMatches[0].Index -ge $endLineMatches[0].Index -or
        $headingMatches.Count -ne 1 -or
        $headingMatches[0].Index -le $beginLineMatches[0].Index -or
        $headingMatches[0].Index -ge $endLineMatches[0].Index) {
        throw 'PACKAGE_INSTRUCTIONS_INVALID: canonical managed section is malformed.'
    }

    return $normalized
}

function Assert-Package {
    param([Parameter(Mandatory = $true)][string]$SkillRoot)

    if (-not (Test-Path -LiteralPath $SkillRoot -PathType Container)) {
        throw 'PACKAGE_INVALID: skill package root is missing.'
    }

    foreach ($relativePath in $canonicalRelativePaths) {
        $path = Join-PortablePath -Root $SkillRoot -RelativePath $relativePath
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw ('PACKAGE_FILE_MISSING: ' + $relativePath)
        }
    }

    foreach ($relativePath in $legacyPackageRelativePaths) {
        if (Test-Path -LiteralPath (Join-PortablePath -Root $SkillRoot -RelativePath $relativePath)) {
            throw ('PACKAGE_INVALID: obsolete Codex artifact is not allowed: ' + $relativePath)
        }
    }

    foreach ($item in Get-ChildItem -LiteralPath $SkillRoot -Recurse -Force) {
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw ('PACKAGE_INVALID: symbolic links or reparse points are not supported: ' + $item.FullName)
        }
    }

    $skillPath = Join-PortablePath -Root $SkillRoot -RelativePath 'SKILL.md'
    $skillText = [IO.File]::ReadAllText($skillPath)
    $skillFrontmatter = Get-YamlFrontmatter -Text $skillText `
        -ErrorMessage 'PACKAGE_SKILL_INVALID: SKILL.md must begin with valid YAML frontmatter.'
    $skillNameFields = @([regex]::Matches($skillFrontmatter, '(?m)^name\s*:'))
    $expectedSkillNames = @([regex]::Matches(
        $skillFrontmatter,
        '(?m)^name:\s*[''"]?luna-subagents[''"]?\s*$'
    ))
    if ($skillNameFields.Count -ne 1 -or $expectedSkillNames.Count -ne 1) {
        throw 'PACKAGE_SKILL_INVALID: SKILL.md name must be luna-subagents.'
    }
    if ($skillText -notmatch '(?im)^\s*model\s*:\s*[''"]?gpt-5\.6-luna[''"]?\s*$') {
        throw 'PACKAGE_SKILL_INVALID: SKILL.md must require model gpt-5.6-luna.'
    }
    if ($skillText -notmatch '(?im)^\s*reasoning_effort\s*:\s*[''"]?max[''"]?\s*$') {
        throw 'PACKAGE_SKILL_INVALID: SKILL.md must require reasoning_effort max.'
    }

    $agentPath = Join-PortablePath -Root $SkillRoot -RelativePath 'assets/agents/luna-subagents-executor.agent.md'
    $agentText = [IO.File]::ReadAllText($agentPath)
    $agentFrontmatter = Get-YamlFrontmatter -Text $agentText `
        -ErrorMessage 'PACKAGE_AGENT_INVALID: executor agent must begin with valid YAML frontmatter.'
    $agentNameFields = @([regex]::Matches($agentFrontmatter, '(?m)^name\s*:'))
    $expectedAgentNames = @([regex]::Matches(
        $agentFrontmatter,
        '(?m)^name:\s*[''"]?luna-subagents-executor[''"]?\s*$'
    ))
    if ($agentNameFields.Count -ne 1 -or $expectedAgentNames.Count -ne 1) {
        throw 'PACKAGE_AGENT_INVALID: executor agent name must be luna-subagents-executor.'
    }
    $modelFields = @([regex]::Matches($agentFrontmatter, '(?m)^model\s*:'))
    $expectedModels = @([regex]::Matches(
        $agentFrontmatter,
        '(?m)^model:\s*[''"]?gpt-5\.6-luna[''"]?\s*$'
    ))
    if ($modelFields.Count -ne 1 -or $expectedModels.Count -ne 1) {
        throw 'PACKAGE_AGENT_INVALID: executor agent must pin model gpt-5.6-luna.'
    }
    $effortFields = @([regex]::Matches($agentFrontmatter, '(?m)^reasoning-effort\s*:'))
    $expectedEfforts = @([regex]::Matches(
        $agentFrontmatter,
        '(?m)^reasoning-effort:\s*[''"]?max[''"]?\s*$'
    ))
    if ($effortFields.Count -ne 1 -or $expectedEfforts.Count -ne 1) {
        throw 'PACKAGE_AGENT_INVALID: executor agent must pin reasoning-effort max exactly once.'
    }

    $instructionsAssetPath = Join-PortablePath -Root $SkillRoot -RelativePath 'assets/global-copilot-instructions-section.md'
    [void](Get-CanonicalManagedBlock -AssetPath $instructionsAssetPath)
}

function Get-InstructionPlan {
    param(
        [Parameter(Mandatory = $true)][string]$InstructionsPath,
        [Parameter(Mandatory = $true)][string]$CanonicalBlock,
        [Parameter()][switch]$Verify
    )

    $errorPrefix = if ($Verify) { 'VERIFY_FAILED' } else { 'COPILOT_INSTRUCTIONS_AMBIGUOUS' }
    $exists = Test-Path -LiteralPath $InstructionsPath
    if ($exists -and -not (Test-Path -LiteralPath $InstructionsPath -PathType Leaf)) {
        throw "${errorPrefix}: copilot-instructions.md exists but is not a file."
    }
    if (-not $exists) {
        if ($Verify) {
            throw 'VERIFY_FAILED: copilot-instructions.md is missing.'
        }
        $newline = [Environment]::NewLine
        return [pscustomobject]@{
            UpdatedText = (Convert-NewlineStyle -Text $CanonicalBlock -Newline $newline) + $newline
            ShouldWrite = $true
        }
    }

    $existingText = [IO.File]::ReadAllText($InstructionsPath)
    $hasByteOrderMark = Test-ByteOrderMark -Path $InstructionsPath
    if ($Verify -and $hasByteOrderMark) {
        throw 'VERIFY_FAILED: copilot-instructions.md must be UTF-8 without a byte-order mark.'
    }

    $newline = Get-NewlineStyle -Text $existingText
    $canonicalForFile = Convert-NewlineStyle -Text $CanonicalBlock -Newline $newline
    $beginTokenCount = ([regex]::Matches($existingText, [regex]::Escape($beginMarker))).Count
    $endTokenCount = ([regex]::Matches($existingText, [regex]::Escape($endMarker))).Count
    $beginLineMatches = @([regex]::Matches(
        $existingText,
        '(?m)^[ \t]*' + [regex]::Escape($beginMarker) + '[ \t]*(?=\r?$)'
    ))
    $endLineMatches = @([regex]::Matches(
        $existingText,
        '(?m)^[ \t]*' + [regex]::Escape($endMarker) + '[ \t]*(?=\r?$)'
    ))
    $headingMatches = @([regex]::Matches(
        $existingText,
        '(?m)^##(?!#)[ \t]+Luna subagent 委派[ \t]*(?=\r?$)'
    ))

    if ($beginTokenCount -ne $endTokenCount -or
        $beginTokenCount -gt 1 -or
        $endTokenCount -gt 1 -or
        ($beginTokenCount -gt 0 -and
        ($beginLineMatches.Count -ne 1 -or $endLineMatches.Count -ne 1))) {
        throw "${errorPrefix}: managed section markers are broken, duplicated, or nested."
    }

    if ($beginTokenCount -eq 1) {
        $beginMatch = $beginLineMatches[0]
        $endMatch = $endLineMatches[0]
        if ($beginMatch.Index -ge $endMatch.Index) {
            throw "${errorPrefix}: managed section markers are out of order."
        }

        $blockStart = $beginMatch.Index
        $blockEnd = $endMatch.Index + $endMatch.Length
        foreach ($headingMatch in $headingMatches) {
            if ($headingMatch.Index -lt $blockStart -or $headingMatch.Index -ge $blockEnd) {
                throw "${errorPrefix}: duplicate '$managedHeading' heading exists outside the managed section."
            }
        }

        $managedText = $existingText.Substring($blockStart, $blockEnd - $blockStart)
        $isCanonical = $managedText -ceq $canonicalForFile
        if ($Verify -and -not $isCanonical) {
            throw 'VERIFY_FAILED: managed section differs from the canonical asset.'
        }

        $updatedText = $existingText.Substring(0, $blockStart) +
            $canonicalForFile +
            $existingText.Substring($blockEnd)
        return [pscustomobject]@{
            UpdatedText = $updatedText
            ShouldWrite = ($updatedText -cne $existingText) -or $hasByteOrderMark
        }
    }

    if ($headingMatches.Count -gt 0) {
        throw "${errorPrefix}: duplicate '$managedHeading' heading exists outside a managed section."
    }
    if ($Verify) {
        throw 'VERIFY_FAILED: canonical managed section is missing from copilot-instructions.md.'
    }

    if ($existingText.Length -eq 0) {
        $updatedText = $canonicalForFile + $newline
    }
    elseif ($existingText.EndsWith("`r`n") -or $existingText.EndsWith("`n")) {
        $updatedText = $existingText + $canonicalForFile + $newline
    }
    else {
        $updatedText = $existingText + $newline + $canonicalForFile + $newline
    }

    return [pscustomobject]@{
        UpdatedText = $updatedText
        ShouldWrite = $true
    }
}

function Copy-PackageTree {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    $sourcePath = Get-NormalizedPath -Path $Source
    $destinationPath = Get-NormalizedPath -Path $Destination
    if (Test-SamePath -First $sourcePath -Second $destinationPath) {
        return
    }
    if (Test-Path -LiteralPath $destinationPath -PathType Leaf) {
        throw 'INSTALL_FAILED: target skill path exists but is not a directory.'
    }

    New-Item -ItemType Directory -Path $destinationPath -Force | Out-Null
    $pathComparer = [StringComparer]::OrdinalIgnoreCase
    $sourceRelativePaths = [Collections.Generic.HashSet[string]]::new($pathComparer)
    foreach ($sourceFile in Get-ChildItem -LiteralPath $sourcePath -Recurse -File -Force) {
        $relativePath = [IO.Path]::GetRelativePath($sourcePath, $sourceFile.FullName)
        [void]$sourceRelativePaths.Add($relativePath)
    }

    foreach ($destinationFile in Get-ChildItem -LiteralPath $destinationPath -Recurse -File -Force) {
        $relativePath = [IO.Path]::GetRelativePath($destinationPath, $destinationFile.FullName)
        if (-not $sourceRelativePaths.Contains($relativePath)) {
            Remove-Item -LiteralPath $destinationFile.FullName -Force
        }
    }

    foreach ($destinationDirectory in @(
        Get-ChildItem -LiteralPath $destinationPath -Recurse -Directory -Force |
            Sort-Object { $_.FullName.Length } -Descending
    )) {
        if (-not (Get-ChildItem -LiteralPath $destinationDirectory.FullName -Force | Select-Object -First 1)) {
            Remove-Item -LiteralPath $destinationDirectory.FullName -Force
        }
    }

    foreach ($sourceFile in Get-ChildItem -LiteralPath $sourcePath -Recurse -File -Force) {
        $relativePath = [IO.Path]::GetRelativePath($sourcePath, $sourceFile.FullName)
        $destinationFile = Join-Path $destinationPath $relativePath
        $destinationDirectory = Split-Path $destinationFile -Parent
        New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
        Copy-Item -LiteralPath $sourceFile.FullName -Destination $destinationFile -Force
    }
}

function Remove-LegacyInstalledFiles {
    param(
        [Parameter(Mandatory = $true)][string]$TargetSkillRoot,
        [Parameter(Mandatory = $true)][string]$TargetAgentRoot
    )

    $legacyPaths = [Collections.Generic.List[string]]::new()
    foreach ($relativePath in $legacyPackageRelativePaths) {
        $legacyPaths.Add((Join-PortablePath -Root $TargetSkillRoot -RelativePath $relativePath))
    }
    foreach ($fileName in $legacyAgentFileNames) {
        $legacyPaths.Add((Join-Path $TargetAgentRoot $fileName))
    }

    foreach ($legacyPath in $legacyPaths) {
        if (Test-Path -LiteralPath $legacyPath -PathType Leaf) {
            Remove-Item -LiteralPath $legacyPath -Force
        }
        elseif (Test-Path -LiteralPath $legacyPath) {
            throw ('INSTALL_FAILED: obsolete artifact path is not a file: ' + $legacyPath)
        }
    }
}

function Assert-Installed {
    param(
        [Parameter(Mandatory = $true)][string]$SourceSkillRoot,
        [Parameter(Mandatory = $true)][string]$TargetHome
    )

    Assert-SafeManagedPaths -TargetHome $TargetHome -ErrorPrefix 'VERIFY_FAILED'
    if (-not (Test-Path -LiteralPath $TargetHome -PathType Container)) {
        throw 'VERIFY_FAILED: Copilot home directory is missing.'
    }

    $targetSkillRoot = Join-PortablePath -Root $TargetHome -RelativePath 'skills/luna-subagents'
    if (-not (Test-Path -LiteralPath $targetSkillRoot -PathType Container)) {
        throw 'VERIFY_FAILED: installed skill package is missing.'
    }

    $sourceManifest = @(
        Get-ChildItem -LiteralPath $SourceSkillRoot -Recurse -File -Force |
            ForEach-Object { [IO.Path]::GetRelativePath($SourceSkillRoot, $_.FullName).Replace('\', '/') } |
            Sort-Object
    )
    $targetManifest = @(
        Get-ChildItem -LiteralPath $targetSkillRoot -Recurse -File -Force |
            ForEach-Object { [IO.Path]::GetRelativePath($targetSkillRoot, $_.FullName).Replace('\', '/') } |
            Sort-Object
    )
    $manifestDifference = @(Compare-Object -ReferenceObject $sourceManifest -DifferenceObject $targetManifest)
    if ($manifestDifference.Count -gt 0) {
        $difference = $manifestDifference[0]
        $kind = if ($difference.SideIndicator -eq '=>') { 'unexpected installed file' } else { 'missing installed file' }
        throw ('VERIFY_FAILED: {0}: {1}' -f $kind, $difference.InputObject)
    }

    foreach ($relativePath in $sourceManifest) {
        $sourcePath = Join-PortablePath -Root $SourceSkillRoot -RelativePath $relativePath
        $targetPath = Join-PortablePath -Root $targetSkillRoot -RelativePath $relativePath
        $sourceHash = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash
        $targetHash = (Get-FileHash -LiteralPath $targetPath -Algorithm SHA256).Hash
        if ($sourceHash -cne $targetHash) {
            throw ('VERIFY_FAILED: installed package file is stale or tampered: ' + $relativePath)
        }
    }

    foreach ($relativePath in $legacyPackageRelativePaths) {
        if (Test-Path -LiteralPath (Join-PortablePath -Root $targetSkillRoot -RelativePath $relativePath)) {
            throw ('VERIFY_FAILED: obsolete Codex artifact remains installed: ' + $relativePath)
        }
    }

    $sourceAgentPath = Join-PortablePath -Root $SourceSkillRoot -RelativePath 'assets/agents/luna-subagents-executor.agent.md'
    $targetAgentRoot = Join-Path $TargetHome 'agents'
    $targetAgentPath = Join-Path $targetAgentRoot $agentFileName
    if (-not (Test-Path -LiteralPath $targetAgentPath -PathType Leaf)) {
        throw ('VERIFY_FAILED: executor agent is missing: ' + $agentFileName)
    }
    $sourceAgentHash = (Get-FileHash -LiteralPath $sourceAgentPath -Algorithm SHA256).Hash
    $targetAgentHash = (Get-FileHash -LiteralPath $targetAgentPath -Algorithm SHA256).Hash
    if ($sourceAgentHash -cne $targetAgentHash) {
        throw ('VERIFY_FAILED: executor agent is stale or tampered: ' + $agentFileName)
    }

    foreach ($fileName in $legacyAgentFileNames) {
        if (Test-Path -LiteralPath (Join-Path $targetAgentRoot $fileName)) {
            throw ('VERIFY_FAILED: obsolete executor profile remains installed: ' + $fileName)
        }
    }

    $instructionsAssetPath = Join-PortablePath -Root $SourceSkillRoot -RelativePath 'assets/global-copilot-instructions-section.md'
    $canonicalBlock = Get-CanonicalManagedBlock -AssetPath $instructionsAssetPath
    $instructionsPath = Join-Path $TargetHome 'copilot-instructions.md'
    [void](Get-InstructionPlan -InstructionsPath $instructionsPath -CanonicalBlock $canonicalBlock -Verify)
}

$sourceSkillRoot = Get-NormalizedPath -Path (Split-Path $PSScriptRoot -Parent)
$targetHome = Resolve-CopilotHome -RequestedPath $CopilotHome
Assert-Package -SkillRoot $sourceSkillRoot
$targetErrorPrefix = if ($Action -eq 'Verify') { 'VERIFY_FAILED' } else { 'INSTALL_FAILED' }
Assert-SafeManagedPaths -TargetHome $targetHome -ErrorPrefix $targetErrorPrefix

if ($Action -eq 'Verify') {
    Assert-Installed -SourceSkillRoot $sourceSkillRoot -TargetHome $targetHome
    Write-Output 'LUNA_SUBAGENTS_VERIFY_OK'
    return
}

if (Test-Path -LiteralPath $targetHome -PathType Leaf) {
    throw 'INSTALL_FAILED: Copilot home exists but is not a directory.'
}

$targetSkillRoot = Join-PortablePath -Root $targetHome -RelativePath 'skills/luna-subagents'
$targetAgentRoot = Join-Path $targetHome 'agents'
$targetAgentPath = Join-Path $targetAgentRoot $agentFileName
$sourceAgentPath = Join-PortablePath -Root $sourceSkillRoot -RelativePath 'assets/agents/luna-subagents-executor.agent.md'
$instructionsAssetPath = Join-PortablePath -Root $sourceSkillRoot -RelativePath 'assets/global-copilot-instructions-section.md'
$canonicalBlock = Get-CanonicalManagedBlock -AssetPath $instructionsAssetPath
$instructionsPath = Join-Path $targetHome 'copilot-instructions.md'
$instructionPlan = Get-InstructionPlan -InstructionsPath $instructionsPath -CanonicalBlock $canonicalBlock

if (-not $PSCmdlet.ShouldProcess(
    $targetHome,
    'Install luna-subagents skill, executor agent, and managed global instructions'
)) {
    Write-Output 'LUNA_SUBAGENTS_INSTALL_PLAN'
    return
}

New-Item -ItemType Directory -Path $targetHome -Force | Out-Null
New-Item -ItemType Directory -Path $targetAgentRoot -Force | Out-Null
Remove-LegacyInstalledFiles -TargetSkillRoot $targetSkillRoot -TargetAgentRoot $targetAgentRoot
Copy-PackageTree -Source $sourceSkillRoot -Destination $targetSkillRoot
Copy-Item -LiteralPath $sourceAgentPath -Destination $targetAgentPath -Force

if ($instructionPlan.ShouldWrite) {
    [IO.File]::WriteAllText(
        $instructionsPath,
        $instructionPlan.UpdatedText,
        [Text.UTF8Encoding]::new($false)
    )
}

Assert-Installed -SourceSkillRoot $sourceSkillRoot -TargetHome $targetHome
Write-Output 'LUNA_SUBAGENTS_INSTALL_OK'
Write-Output 'RELOAD_REQUIRED: Run /skills reload, then restart Copilot CLI or start a new session.'
