# PowerShell Module: InteractiveMenu.psm1
# Refactored from uploaded InteractiveMenu.ps1

# PowerShell Module: InteractiveMenu.psm1
# Refactored from uploaded InteractiveMenu.ps1 into a production-ready module (Option A)
# Module design:
#  - Exports a minimal public surface: Initialize-InteractiveMenu, Show-InteractiveMenu, Add-InteractiveMenuItem,
#    Remove-InteractiveMenuItem, Get-InteractiveMenuConfig, Save-InteractiveMenuConfig, Load-InteractiveMenuConfig
#  - Keeps implementation details in private functions
#  - Module-scoped state lives in $script:MenuState
#  - Supports theme files, persistent config (JSON), dynamic item population, and verbose logging
#  - Comment-based help included for exported cmdlets
# Requires PowerShell 5.1+ / PowerShell Core

# ------------------------- Module-scoped state -------------------------
if (-not $script:MenuState) {
    $script:MenuState = [ordered]@{
        MenuItems = @()
        Title = 'Interactive Menu'
        Width = 80
        Height = 20
        Theme = [ordered]@{
            Background = 'Black'
            Foreground = 'White'
            HighlightBg = 'DarkCyan'
            HighlightFg = 'Black'
            HeaderBg = 'DarkGray'
            HeaderFg = 'White'
        }
        ConfigPath = "$env:USERPROFILE\.interactive-menu\config.json"
        VerboseLogging = $false
        LastResult = $null
    }
}
#endregion
#region------------------------- Helper: logging -------------------------
function Private-Log {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [switch]$Verbose
    )
    if ($script:MenuState.VerboseLogging -or $Verbose) {
        $ts = (Get-Date).ToString('s')
        Write-Verbose "$ts - $Message"
    }
}
#endregion
#region ------------------------- Config persistence -------------------------
function Private-Ensure-ConfigDirectory {
    $dir = [System.IO.Path]::GetDirectoryName($script:MenuState.ConfigPath)
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

function Save-InteractiveMenuConfig {
    <#
      .SYNOPSIS
          Save current menu configuration to disk (JSON)
      .DESCRIPTION
          Persists $script:MenuState to the configured ConfigPath as JSON.
      .EXAMPLE
          Save-InteractiveMenuConfig -Path $env:USERPROFILE\.interactive-menu\myconfig.json
    #>
    param(
        [string]$Path
n    )
    if ($Path) { $script:MenuState.ConfigPath = $Path }
    Private-Ensure-ConfigDirectory
    $toSave = $script:MenuState | ConvertTo-Json -Depth 5
    $script:MenuState.VerboseLogging | Out-Null
    try {
        $toSave | Set-Content -Path $script:MenuState.ConfigPath -Encoding UTF8
        Private-Log "Saved config to $($script:MenuState.ConfigPath)" -Verbose
        return $true
    }
    catch {
        Write-Warning "Failed to save config: $_"
        return $false
    }
}

function Load-InteractiveMenuConfig {
    <#
      .SYNOPSIS
          Load menu configuration from disk
    #>
    param(
        [string]$Path
n    )
    if ($Path) { $script:MenuState.ConfigPath = $Path }
    if (Test-Path $script:MenuState.ConfigPath) {
        try {
            $json = Get-Content -Path $script:MenuState.ConfigPath -Raw -ErrorAction Stop
            $obj = $json | ConvertFrom-Json -Depth 5
            foreach ($k in $obj.PSObject.Properties.Name) {
                $script:MenuState[$k] = $obj.$k
            }
            Private-Log "Loaded config from $($script:MenuState.ConfigPath)" -Verbose
            return $true
        }
        catch {
            Write-Warning "Failed to load config: $_"
            return $false
        }
    }
    else {
        Private-Log "No config found at $($script:MenuState.ConfigPath)" -Verbose
        return $false
    }
}

function Get-InteractiveMenuConfig {
    <#
      .SYNOPSIS
          Returns the current in-memory menu configuration object
    #>
    return $script:MenuState
}

#endregion
#region------------------------- Menu item management -------------------------
function Add-InteractiveMenuItem {
    <#
      .SYNOPSIS
          Add a menu item to the interactive menu
      .PARAMETER Id
          A unique identifier for the menu item
      .PARAMETER Label
          Text to show in the menu
      .PARAMETER Action
          ScriptBlock or string command to execute when chosen
      .PARAMETER Type
          Optional type string for grouping (default: 'Action')
      .EXAMPLE
          Add-InteractiveMenuItem -Id 'vm-start' -Label 'Start VM' -Action { Start-VM -Name $vm }
    #>
    param(
        [Parameter(Mandatory=$true)][string]$Id,
        [Parameter(Mandatory=$true)][string]$Label,
        [Parameter(Mandatory=$true)][object]$Action,
        [string]$Type = 'Action',
        [hashtable]$Meta
    )
    if ($script:MenuState.MenuItems.Id -contains $Id) {
        throw "Menu item with Id '$Id' already exists."
    }
    $item = [ordered]@{
        Id = $Id
        Label = $Label
        Action = $Action
        Type = $Type
        Meta = $Meta
    }
    $script:MenuState.MenuItems += $item
    Private-Log "Added menu item: $Id" -Verbose
    return $item
}

function Remove-InteractiveMenuItem {
    <# .SYNOPSIS Remove a menu item by Id #>
    param([Parameter(Mandatory=$true)][string]$Id)
    $existing = $script:MenuState.MenuItems | Where-Object { $_.Id -eq $Id }
    if (-not $existing) { return $false }
    $script:MenuState.MenuItems = $script:MenuState.MenuItems | Where-Object { $_.Id -ne $Id }
    Private-Log "Removed menu item: $Id" -Verbose
    return $true
}
#endregion
#region------------------------- Rendering -------------------------
function Private-Render-Header {
    param([string]$Title)
    $width = $script:MenuState.Width
    $title = " $Title " -f
    $pad = [Math]::Max(0, ($width - $title.Length) / 2)
    Write-Host (' ' * $width) -NoNewline
    Write-Host
    Write-Host $Title -ForegroundColor $script:MenuState.Theme.HeaderFg -BackgroundColor $script:MenuState.Theme.HeaderBg
}

function Private-Render-Menu {
    param([array]$Items, [int]$SelectedIndex)
    Clear-Host
    Private-Render-Header -Title $script:MenuState.Title
    for ($i=0; $i -lt $Items.Count; $i++) {
        $item = $Items[$i]
        if ($i -eq $SelectedIndex) {
            Write-Host " > $($item.Label)" -BackgroundColor $script:MenuState.Theme.HighlightBg -ForegroundColor $script:MenuState.Theme.HighlightFg
        }
        else {
            Write-Host "   $($item.Label)" -ForegroundColor $script:MenuState.Theme.Foreground
        }
    }
    Write-Host "`nUse Up/Down to navigate, Enter to select, Esc to exit." -ForegroundColor $script:MenuState.Theme.Foreground
}
#endregion
#region------------------------- Input loop / Execution -------------------------
function Show-InteractiveMenu {
    <#
      .SYNOPSIS
          Show the interactive menu UI and handle input
      .DESCRIPTION
          Renders the menu and handles keyboard navigation. When an item is selected
          its Action is invoked. Supports ScriptBlock actions or string commands.
      .EXAMPLE
          Show-InteractiveMenu
    #>
    param(
        [switch]$NoLoop
    )
    if (-not $script:MenuState.MenuItems -or $script:MenuState.MenuItems.Count -eq 0) {
        Write-Warning "No menu items configured. Add items with Add-InteractiveMenuItem."
        return
    }

    $selected = 0
    $items = $script:MenuState.MenuItems

    while ($true) {
        Private-Render-Menu -Items $items -SelectedIndex $selected
        $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        switch ($key.VirtualKeyCode) {
            38 { # Up
                $selected = [Math]::Max(0, $selected - 1)
            }
            40 { # Down
                $selected = [Math]::Min($items.Count - 1, $selected + 1)
            }
            13 { # Enter
                $choice = $items[$selected]
                try {
                    if ($choice.Action -is [scriptblock]) {
                        Private-Log "Invoking scriptblock for $($choice.Id)" -Verbose
                        $result = & $choice.Action
                    }
                    else {
                        Private-Log "Invoking command string for $($choice.Id): $($choice.Action)" -Verbose
                        Invoke-Expression $choice.Action
                    }
                    $script:MenuState.LastResult = $result
                }
                catch {
                    Write-Warning "Action failed: $_"
                }
                if ($NoLoop) { break }
            }
            27 { # Esc
                break
            }
        }
    }
}
#endregion
#region------------------------- Public initialization -------------------------
function Initialize-InteractiveMenu {
    <#
      .SYNOPSIS
          Initialize the menu module and optionally load configuration
      .PARAMETER ConfigPath
          Path to JSON config to load
      .PARAMETER Theme
          Hashtable of theme values to override defaults
      .PARAMETER Verbose
          Turn on verbose logging
    #>
    param(
        [string]$ConfigPath,
        [hashtable]$Theme,
        [switch]$Verbose
    )
    if ($Verbose) { $script:MenuState.VerboseLogging = $true }
    if ($ConfigPath) { $script:MenuState.ConfigPath = $ConfigPath }
    if ($Theme) {
        foreach ($k in $Theme.Keys) { $script:MenuState.Theme[$k] = $Theme[$k] }
    }
    Load-InteractiveMenuConfig -Path $script:MenuState.ConfigPath | Out-Null
    Private-Log "InteractiveMenu initialized" -Verbose
}
#endregion
#region------------------------- Convenience: Build menu from data -------------------------
function Private-Build-MenuFromHashTable {
    param([hashtable]$Spec)
    # Spec should contain arrays of items: @{ Items = @(@{Id='x'; Label='X'; Action={}}) }
    if ($Spec.Items) {
        foreach ($it in $Spec.Items) {
            Add-InteractiveMenuItem -Id $it.Id -Label $it.Label -Action $it.Action -Type $it.Type -Meta $it.Meta | Out-Null
        }
    }
}

# ------------------------- Module exported functions -------------------------
Export-ModuleMember -Function Initialize-InteractiveMenu, Show-InteractiveMenu, Add-InteractiveMenuItem, Remove-InteractiveMenuItem, Get-InteractiveMenuConfig, Save-InteractiveMenuConfig, Load-InteractiveMenuConfig

#endregion
#region------------------------- Developer notes -------------------------
<#
Next steps I can take for you (choose one):
 - Split this into a directory structure with Private/ Public files and produce InteractiveMenu.psd1 manifest
 - Create unit test stubs using Pester
 - Auto-generate README and example usage
 - Add dynamic discovery helpers (Get-VM menu population, Get-VM actions) based on your environment

If you want the full module folder (psm1 + psd1 + Public/Private files) packaged, say "package it" and I'll create the remaining files and export them into the canvas.
#>

# SIG # Begin signature block
# MIIFvwYJKoZIhvcNAQcCoIIFsDCCBawCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCB3NmVw+l5gJdbF
# +z3FsNXUY951LMvUQ9JD/TJ6BpmGfKCCAyYwggMiMIICCqADAgECAhBTL0G9/1qW
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
# LwYJKoZIhvcNAQkEMSIEIG6K1t+TiQUALlrcokwoVIN1YCtB8Tna6qxQwHadCCT7
# MA0GCSqGSIb3DQEBAQUABIIBAGVpHTP8VC5Y4WtXi8z/BJguCZ9VrOkOOuPuRt5p
# 48+d2QPzkuZsAUEQIyPBGkpoP5tcSJkWLEL3zFcTAI1KNzPcFpXoU1sNyRmNTLcH
# jpKTAWRZmrL4Y7JGBDMRCbN9M73Sy9giZr/WJpCuduLLOK+axIA4PO/r53SgzYke
# NOOowsVV1u/YLgdjJA2zP6+bbWSHJTXYSd07zG8fzdtlGurY2whEw9vBtBT7VtLY
# s6glLjS63uIMYwXwbxDKN3obxs+Euk9pE9Xm+sUP0mhyXkg6TpWqFwC1ih81fSlq
# T056djPnR7b4JDIIHqYS9F0PE3Qjn1rvcGvMypRhBqZWneU=
# SIG # End signature block
