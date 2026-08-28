@echo off
setlocal EnableExtensions DisableDelayedExpansion
set "ERRORLEVEL="
set "LUNA_INSTALLER=%~dp0install.ps1"
set "LUNA_ARG_COUNT=0"

:collect-args
if "%~1"=="" goto :check-empty-arg
:store-arg
set "LUNA_ARG_%LUNA_ARG_COUNT%=%~1"
set /a LUNA_ARG_COUNT+=1 >nul
shift
goto :collect-args

:check-empty-arg
if "%1"=="" goto :args-collected
goto :store-arg

:args-collected

where.exe pwsh.exe >nul 2>&1
if not errorlevel 1 goto :probe-pwsh
goto :try-windows-powershell

:probe-pwsh
pwsh.exe -NoLogo -NoProfile -Command "if ($PSVersionTable.PSVersion.Major -ge 7) { exit 0 } else { exit 1 }" >nul 2>&1
if not errorlevel 1 goto :select-pwsh
goto :try-windows-powershell

:select-pwsh
set "LUNA_RUNTIME=pwsh.exe"
set "LUNA_HOST=pwsh"
goto :run-installer

:try-windows-powershell
set "LUNA_WINDOWS_POWERSHELL=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%LUNA_WINDOWS_POWERSHELL%" goto :no-runtime
"%LUNA_WINDOWS_POWERSHELL%" -NoLogo -NoProfile -Command "if (($PSVersionTable.PSVersion.Major -gt 5) -or (($PSVersionTable.PSVersion.Major -eq 5) -and ($PSVersionTable.PSVersion.Minor -ge 1))) { exit 0 } else { exit 1 }" >nul 2>&1
if errorlevel 1 goto :no-runtime
set "LUNA_RUNTIME=%LUNA_WINDOWS_POWERSHELL%"
set "LUNA_HOST=windows-powershell"
goto :run-installer

:run-installer
echo LUNA_POWERSHELL_HOST=%LUNA_HOST%
"%LUNA_RUNTIME%" -NoLogo -NoProfile -Command "$ErrorActionPreference = 'Stop'; $count = [int]$env:LUNA_ARG_COUNT; $tokens = @(); for ($i = 0; $i -lt $count; $i++) { $tokens += [Environment]::GetEnvironmentVariable(('LUNA_ARG_' + $i)) }; $action = 'Install'; $copilotHomeValue = $null; $whatIf = $false; $confirm = $null; $seen = @{}; for ($i = 0; $i -lt $tokens.Count; $i++) { $token = $tokens[$i]; if ($token -ieq '-Action') { if ($seen.ContainsKey('Action')) { throw 'LUNA_ARGUMENT_ERROR: duplicate -Action.' }; $i++; if ($i -ge $tokens.Count -or [string]::IsNullOrWhiteSpace($tokens[$i]) -or $tokens[$i].StartsWith('-')) { throw 'LUNA_ARGUMENT_ERROR: missing value for -Action.' }; $action = $tokens[$i]; if (($action -ine 'Install') -and ($action -ine 'Verify')) { throw 'LUNA_ARGUMENT_ERROR: -Action must be Install or Verify.' }; $seen['Action'] = $true } elseif ($token -ieq '-CopilotHome') { if ($seen.ContainsKey('CopilotHome')) { throw 'LUNA_ARGUMENT_ERROR: duplicate -CopilotHome.' }; $i++; if ($i -ge $tokens.Count -or [string]::IsNullOrWhiteSpace($tokens[$i]) -or $tokens[$i].StartsWith('-')) { throw 'LUNA_ARGUMENT_ERROR: missing value for -CopilotHome.' }; $copilotHomeValue = $tokens[$i]; $seen['CopilotHome'] = $true } elseif (($token -ieq '-WhatIf') -or ($token -ieq '-WhatIf:$true') -or ($token -ieq '-WhatIf:$false')) { if ($seen.ContainsKey('WhatIf')) { throw 'LUNA_ARGUMENT_ERROR: duplicate -WhatIf.' }; $whatIf = ($token -ieq '-WhatIf') -or ($token -ieq '-WhatIf:$true'); $seen['WhatIf'] = $true } elseif (($token -ieq '-Confirm') -or ($token -ieq '-Confirm:$true') -or ($token -ieq '-Confirm:$false')) { if ($seen.ContainsKey('Confirm')) { throw 'LUNA_ARGUMENT_ERROR: duplicate -Confirm.' }; $confirm = ($token -ieq '-Confirm') -or ($token -ieq '-Confirm:$true'); $seen['Confirm'] = $true } else { throw 'LUNA_ARGUMENT_ERROR: unknown or unsupported argument.' } }; $bound = @{ Action = $action }; if ($null -ne $copilotHomeValue) { $bound['CopilotHome'] = $copilotHomeValue }; if ($whatIf) { $bound['WhatIf'] = $true }; if ($null -ne $confirm) { $bound['Confirm'] = $confirm }; & $env:LUNA_INSTALLER @bound; if (-not $?) { exit 1 }"
set "LUNA_CHILD_EXIT=%errorlevel%"
exit /b %LUNA_CHILD_EXIT%

:no-runtime
>&2 echo LUNA_POWERSHELL_ERROR=No usable PowerShell runtime found.
exit /b 1
