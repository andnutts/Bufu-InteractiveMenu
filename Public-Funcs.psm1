#==========================================#
# Public Functions
#==========================================#
function Get-MenuTitle {
    <#
      .SYNOPSIS
          Converts a file or folder name into a spaced menu title.
      .DESCRIPTION
          Strips extensions, replaces hyphens/underscores with spaces,
          and inserts spaces between camel-cased words.
      .PARAMETER Path
          Full or relative path to the script file. If omitted, the function
          will attempt to determine the calling script's file name automatically.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Path
    )
    #region --- Try caller's PSCommandPath (script scope) ---
    if (-not $Path) {
        $callerPSCommandPath = (Get-Variable -Name PSCommandPath -Scope 1 -ErrorAction SilentlyContinue).Value
        if ($callerPSCommandPath) {
            $Path = $callerPSCommandPath
        }
    }
    #endregion
    #region --- Search the call stack for the first frame with a ScriptName ---
    if (-not $Path) {
        $callStack = Get-PSCallStack
        foreach ($frame in $callStack) {
            if ($frame.ScriptName) {
                $Path = $frame.ScriptName
                break
            }
        }
    }
    #endregion
    #region --- This invocation's script or command path ---
    if (-not $Path) {
        if ($MyInvocation.ScriptName) {
            $Path = $MyInvocation.ScriptName
        } elseif ($MyInvocation.MyCommand.Path) {
            $Path = $MyInvocation.MyCommand.Path
        } elseif ($MyInvocation.MyCommand.Definition) {
            $Path = $MyInvocation.MyCommand.Definition
        }
    }
    #endregion
    #region --- Fallback to current directory path ---
    if (-not $Path) {
        $Path = (Get-Location).Path
    }
    #endregion
    #region --- Use directory name if Path is a container; otherwise file name without extension ---
    if (Test-Path -Path $Path -PathType Container) {
        $baseName = Split-Path -Leaf $Path
    } else {
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($Path)
    }
    #endregion
    # Replace separators with spaces and insert spaces before camel-case capitals
    $withSpaces = $baseName -replace '[-_]', ' '
    $title = ($withSpaces -creplace '([a-z0-9])([A-Z])', '$1 $2').Trim()
    return $title
}

function Invoke-ActionById {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][psobject]$Context,
        [hashtable]$Options
    )

    if (-not $ActionRegistry.ContainsKey($Id)) { throw "Action '$Id' not registered" }

    $sb = $ActionRegistry[$Id]

    # Decide call style: prefer context-aware signature if action declares a param
    $usesContextParam = $false
    try {
        $params = $sb.Parameters
        if ($params.Count -gt 0) {
            # If first parameter name looks like 'ctx' or 'Context' or has no name but is positional, assume context-accepting
            $firstName = $params[0].Name
            if ($firstName -match '^(ctx|context|c)$' -or $params[0].Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } ) {
                $usesContextParam = $true
            } else {
                # fallback: if there is at least one parameter, assume it's context
                $usesContextParam = $true
            }
        }
    } catch {
        # If introspection fails, assume old-style (no context param)
        $usesContextParam = $false
    }

    # Call the action and capture result
    $result = $null
    if ($usesContextParam) {
        try {
            $result = & $sb $Context
        } catch {
            throw "Action '$Id' failed: $($_.Exception.Message)"
        }
    } else {
        # Old-style action: invoke without context
        try {
            $result = & $sb
        } catch {
            throw "Action '$Id' failed: $($_.Exception.Message)"
        }
    }

    # If action returned a Context-like PSCustomObject, use it
    if ($result -and ($result -is [psobject]) -and ($result.PSObject.Properties.Name -contains 'Psm1Path' -or $result.PSObject.TypeNames -contains 'System.Management.Automation.PSCustomObject')) {
        return $result
    }

    # No context returned: rehydrate from globals using provided map or default map
    $rehydrateMap = if ($Options -and $Options.RehydrateMap) { $Options.RehydrateMap } else { $DefaultRehydrateMap }

    foreach ($key in $rehydrateMap.Keys) {
        try {
            $val = & $rehydrateMap[$key]
        } catch {
            $val = $null
        }
        if ($null -ne $val) {
            # create or update property on Context
            if ($Context.PSObject.Properties.Match($key).Count -eq 0) {
                $Context | Add-Member -MemberType NoteProperty -Name $key -Value $val
            } else {
                $Context.$key = $val
            }
        }
    }

    # update LastUsed/time
    if ($Context.PSObject.Properties.Match('LastUsed').Count -eq 0) {
        $Context | Add-Member -MemberType NoteProperty -Name 'LastUsed' -Value (Get-Date)
    } else {
        $Context.LastUsed = (Get-Date)
    }

    return $Context
}

function Show-InteractiveMenu {
    <#
        .SYNOPSIS
            Displays an interactive, centralized, and color-coded console menu.
        .DESCRIPTION
            This function renders a list of menu items and switches, allowing
            the user to navigate using arrow keys or numeric input, toggle
            features, and execute associated scripts or scriptblocks.
        .PARAMETER MenuData
            A Hashtable defining the menu options. Keys are used for stable ordering.
            Each value must be a PSCustomObject with a 'Name' property.
            It should also have *either* an 'Action' property (a ScriptBlock)
            *or* 'File' and 'Type' properties for launching external files.
            Example (ScriptBlock): @{'1' = @{Name='Run Task'; Action={...}}}
            Example (File): @{'2' = @{Name='Convert'; File='script.py'; Type='CMD'}}
        .PARAMETER MenuSwitches
            An optional array of PSCustomObject switches. If not provided, the default
            (Debug, Navigation, Dry-Run) set is used. Each switch must have Id, Name, State, and Type.
        .PARAMETER Title
            The title displayed at the top of the menu.
        .PARAMETER ScriptDir
            The directory containing the files specified in MenuData (if using file-based entries).
        .PARAMETER EnablePersistence
            If specified, the states of the switches (D, N, R, etc.) are saved to a
            JSON file in the user's profile directory and loaded on next execution.
        .EXAMPLE
            $MyMenu = @{
                '1' = [PSCustomObject]@{ Name = 'Generate Report'; Action = { Write-Host "Report..." } }
                '2' = [PSCustomObject]@{ Name = 'Launch GUI Tool'; File = 'gui.py'; Type = 'GUI' }
            }
            Show-InteractiveMenu -MenuData $MyMenu -ScriptDir "C:\MyTools\Scripts" -EnablePersistence
    #>
    param(
        [Parameter(Mandatory)][object]$MenuData,
        [array]$MenuSwitches = $DefaultSwitches,
        [string]$Title,
        [string]$SubTitle,
        [string]$ScriptDir = (Get-Location).Path,
        [switch]$EnablePersistence
    )
    #region 1. Prepare persistence path if enabled
    $persistencePath = $null
    if ($EnablePersistence) {
        $persistencePath = "$env:USERPROFILE\PowershellMenuStates.json"
        Load-SwitchStates -MenuSwitches $MenuSwitches -Path $persistencePath | Out-Null
    }
    #endregion
    #region 2. Normalize MenuData to ordered $menuItems
    $menuItems = @()

    if ($MenuData -is [System.Collections.Hashtable]) {
        $menuKeys = $MenuData.Keys | Sort-Object
        foreach ($k in $menuKeys) {
            $item = $MenuData[$k]
            if (-not $item.PSObject.Properties['Key']) {
                $item | Add-Member -MemberType NoteProperty -Name 'Key' -Value $k -PassThru | Out-Null
            } else {
                $item.Key = $k
            }
            $menuItems += $item
        }
    } elseif ($MenuData -is [System.Array] -or $MenuData -is [System.Collections.IEnumerable]) {
        # Accept arrays or any enumerable (ordered). Use index as Key if not present.
        $i = 0
        foreach ($item in $MenuData) {
            if (-not $item.PSObject.Properties['Key']) {
                $item | Add-Member -MemberType NoteProperty -Name 'Key' -Value $i -PassThru | Out-Null
            } else {
                $item.Key = $item.Key
            }
            $menuItems += $item
            $i++
        }
    } else {
        throw "Unsupported MenuData type: $($MenuData.GetType().FullName). Provide a hashtable or array of menu items."
    }

    if ($menuItems.Count -eq 0) {
        Write-Host "Error: MenuData is empty." -ForegroundColor Red
        return
    }
    #endregion
    #region 3. Get initial state for local variables
    $selected = 0
    $quit = $false
    #endregion
    #region 4. Main Menu Loop
    do {
        $mode = (Get-SwitchById -MenuSwitches $MenuSwitches -Id 'N').State
        #region 4a. Render the menu
        Render-FullMenu -Selected $selected -Mode $mode -MenuSwitches $MenuSwitches -MenuItems $menuItems -Title $Title -ScriptDir $ScriptDir
        #endregion
        #region 4b. Read Key Input
        $keyInfo = Read-MenuKey -MenuSwitches $MenuSwitches -Mode $mode
        $actionTaken = $false
        #endregion
        #region 4c. Handle Key input
        try {
            switch ($keyInfo.Intent) {
                'Up' {
                    $selected = ($selected - 1) % $menuItems.Count
                    if ($selected -lt 0) { $selected = $menuItems.Count - 1 }
                    $actionTaken = $true
                }
                'Down' {
                    $selected = ($selected + 1) % $menuItems.Count
                    $actionTaken = $true
                }
                'Enter' {
                    $entry = $menuItems[$selected]
                    $invokeResult = Invoke-MenuEntry -Entry $entry -ScriptDir $ScriptDir -MenuSwitches $MenuSwitches
                    if ($invokeResult -eq 'quit') { $quit = $true }
                    else { Read-Host "`nPress [Enter] to return to menu..." | Out-Null }
                    $actionTaken = $true
                }
                'Number' {
                    $index = $keyInfo.Number - 1
                    if ($index -ge 0 -and $index -lt $menuItems.Count) {
                        $entry = $menuItems[$index]
                        $invokeResult = Invoke-MenuEntry -Entry $entry -ScriptDir $ScriptDir -MenuSwitches $MenuSwitches
                        $selected = $index
                        if ($invokeResult -eq 'quit') {
                            $quit = $true
                        } else {
                            Read-Host "`nPress [Enter] to return to menu..." | Out-Null
                        }
                        $actionTaken = $true
                    }
                }
                'Switch' {
                    $s = Get-SwitchById -MenuSwitches $MenuSwitches -Id $keyInfo.SwitchId
                    if ($s.Type -eq 'Toggle') {
                        Set-SwitchState -MenuSwitches $MenuSwitches -Id $keyInfo.SwitchId
                        $actionTaken = $true
                    } elseif ($s.Type -eq 'Choice' -and $keyInfo.SwitchId -eq 'N') {
                        $current = $s.State
                        $new = if ($current -eq 'Arrow') { 'Numeric' } else { 'Arrow' }
                        Set-SwitchState -MenuSwitches $MenuSwitches -Id 'N' -State $new
                        $actionTaken = $true
                    }
                }
                'Quit' { $quit = $true; $actionTaken = $true }
                'Escape' { $quit = $true; $actionTaken = $true }
                default { }
            }
            if ($EnablePersistence -and $actionTaken -and $keyInfo.Intent -in @('Switch', 'Quit', 'Escape')) {
                 Save-SwitchStates -MenuSwitches $MenuSwitches -Path $persistencePath | Out-Null
            }
        #endregion
        #region 4d. Handle Errors
        } catch {
            Write-Colored -Text "`nERROR: $($_.Exception.Message)`n" -Fg 'White' -Bg 'DarkRed'
            Read-Host "`nPress [Enter] to continue..." | Out-Null
        }
        #endregion
    } while (-not $quit)
    #endregion
    #region 5. Cleanup
    [Console]::ResetColor()
    try { Clear-Host } catch {}
    #endregion
}

# SIG # Begin signature block
# MIIFvwYJKoZIhvcNAQcCoIIFsDCCBawCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCB5sGSW8cf9uPxd
# 1Yu8S0dm/ZMnx1Jwy1/surfbRWl5m6CCAyYwggMiMIICCqADAgECAhBTL0G9/1qW
# u0vZWRqoGigBMA0GCSqGSIb3DQEBCwUAMCkxJzAlBgNVBAMMHlNldEVudkludGVy
# YWN0aXZlIENvZGUgU2lnbmluZzAeFw0yNTEyMTExNjE2MDdaFw0zMDEyMTExNjI2
# MDdaMCkxJzAlBgNVBAMMHlNldEVudkludGVyYWN0aXZlIENvZGUgU2lnbmluZzCC
# ASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAMINkqJcrKIzkS6j5yHr4BRQ
# sxbufzzhaTcFk5GPw9MBm2w4728lOUg8XWxF0PB1nNz9SeQnSV+/v7nXE/siXOni
# f77MRhzqjwYvYVNnueXg+En+TeCfLsVJ3xL+/Dum+GDo0MGBA+/Xz/3HTNtMZzHU
# qO92G3t36C8rJaEU0NfV6MOn7pQUcDyNUKXcPnFADMn23V1JhTqYe3DI1/Qe2TJ3
# pFkh72IJ7Zq4fn6egOlYaPbxxOnLA8e4WizW/OEP7SG7gFn/0skeslbB8ICs0U9x
# TdFsUNgK+W1SkJL8LqRTnbG0LqiYBHqa+kzLN7zPAzaCllaZbXkKhl2dz6n89nEC
# AwEAAaNGMEQwDgYDVR0PAQH/BAQDAgeAMBMGA1UdJQQMMAoGCCsGAQUFBwMDMB0G
# A1UdDgQWBBQHDipZfdXTdLr+9/8M/LJlU+lKITANBgkqhkiG9w0BAQsFAAOCAQEA
# QamQPBxTtg+sE9mApfJMOMuFR3iBOJL/7gjgONmbh5vfv6YBX3rF5Povf6bqXgJr
# 37yR1siuZRFw65hprf8mkx47rIRKgDGeJ7/lKtkvJjW1mPFC5TDqGfMcfsSmH8wD
# VcSR8RdTTCP+s3cco6vaAvJHqtFi2omzUbhbPNDExjAvm+6ctauqMmAisfU0xuW+
# SNNz7FdcQbfoVwq9SionBeC6F+phSQM265IGBnTmpkInoedqwwMDejnTmTiLuatr
# 42yxv4IoJcqjjhF5lxT7Vj/RW+MdPGpRoCYDQ0shXOu4vh5RerTIIrS2m8XZl5gN
# N5Vhd+hERzeerNtkHWyD7jGCAe8wggHrAgEBMD0wKTEnMCUGA1UEAwweU2V0RW52
# SW50ZXJhY3RpdmUgQ29kZSBTaWduaW5nAhBTL0G9/1qWu0vZWRqoGigBMA0GCWCG
# SAFlAwQCAQUAoIGEMBgGCisGAQQBgjcCAQwxCjAIoAKAAKECgAAwGQYJKoZIhvcN
# AQkDMQwGCisGAQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUw
# LwYJKoZIhvcNAQkEMSIEILlmAls5O75BKRs9KHX07UolLxfLg8nt6qEQn0Lmm/Tn
# MA0GCSqGSIb3DQEBAQUABIIBADGQZfF9y86Te+g+upARAOB/4X7+QjxoefPqPIo+
# mdjzwORReyqBT90aZCSEnlzbHWHncu1xZ615GIRA5f6BGr8weGX4wQ6g7YcVTTcy
# q9BNZ47j5b+Bken+v3TRK4POsREnlY3EIz+tVH3X12F/wVhRw/Z3hVLI4cFOgBfa
# 3SjAIDc7bzgcH0oSwCBLJvbjut7yFsdCTNzcHWt7udcnqemGY/mSHTLr5pYEM4GL
# xvpRDWH2l2UakmNWfMnoA4hl+lTy3v1lFas1dKfHqwVEUVNBZPKks+/KlyYPy7o3
# utQ86LhSgjM1Y2cczABEyqnpunUCS5y0nORs3I2GRhHYtxs=
# SIG # End signature block
