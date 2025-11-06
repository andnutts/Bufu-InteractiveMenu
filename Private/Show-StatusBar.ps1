function Show-StatusBar {
    <#
      .SYNOPSIS
        Displays status information centered in the console.
      .DESCRIPTION
        Shows user, host, debug/dry-run states and optionally execution path.
      .PARAMETER ScriptDir
        Script directory or path to optionally display.
      .PARAMETER MenuSwitches
        Array of switch objects used to detect toggles (D, R, N, E).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$ScriptDir,
        [Parameter(Mandatory=$false)][array]$MenuSwitches = @()
    )
    try { $navMode      = [string](Get-SwitchById -MenuSwitches $MenuSwitches -Id 'N').State } catch { $navMode       = $GlobalConfig.DefaultMenuMode }
    try { $debug        = [bool](Get-SwitchById -MenuSwitches $MenuSwitches -Id 'D').State   } catch { $debug         = $false }
    try { $dryRun       = [bool](Get-SwitchById -MenuSwitches $MenuSwitches -Id 'R').State   } catch { $dryRun        = $false }

    $debugText  = if ($debug)   { $GlobalConfig.SwitchOnText } else { $GlobalConfig.SwitchOffText }
    $dryRunText = if ($dryRun)  { $GlobalConfig.SwitchOnText } else { $GlobalConfig.SwitchOffText }
    $navMode    = if ($navMode -eq 'Arrow') { 'Arrow' } else { 'Numeric' }

    $user = [Environment]::UserName
    $hostName = $env:COMPUTERNAME

    $status = "User: $user | Host: $hostName | DEBUG: $debugText | DRY-RUN: $dryRunText | Nav: $navMode"
    $parts = $status -split '\s*\|\s*'
    $parts = $status.Split(' | ')
    $statusBarParts = @(
        @{ Id='User';           Text="User: $user ";        Value=$user;        
            Fg=$GlobalConfig.InfoColor
            Bg=$GlobalConfig.BackgroundColor }
        @{ Id='Host';           Text="Host: $hostName";     Value=$hostName
            Fg=$GlobalConfig.InfoColor
            Bg=$GlobalConfig.BackgroundColor }
        @{ Id='debug';          Text="DEBUG: $debugText";   Value=$debugText
            textFg=$GlobalConfig.InfoColor
            textBg=$GlobalConfig.BackgroundColor
            Fg=if ($debug) { $GlobalConfig.ToggleOnFg } else { $GlobalConfig.MutedColor }
            Bg=if ($debug) { $GlobalConfig.ToggleOnBg } else { $GlobalConfig.BackgroundColor } }
        @{ Id='dryRunLabel';    Text=" | DRY-RUN: "
            Fg=$GlobalConfig.InfoColor
            Bg=$GlobalConfig.BackgroundColor }
        @{ Id='dryRunValue';    Text=$dryRunText
            Fg=if ($dryRun) { $GlobalConfig.ToggleOnFg } else { $GlobalConfig.MutedColor }
            Bg=if ($dryRun) { $GlobalConfig.ToggleOnBg } else { $GlobalConfig.BackgroundColor } }
        @{ Id='Nav';            Text="Nav: $navMode";       Value=$navMode
            Fg=$GlobalConfig.InfoColor
            Bg=$GlobalConfig.BackgroundColor }
            Fg=if ($navMode -eq 'Arrow') { $GlobalConfig.SelectedTextColor } else { $GlobalConfig.InfoColor }
            Bg=if ($navMode -eq 'Arrow') { $GlobalConfig.SelectedTextBg } else { $GlobalConfig.BackgroundColor }
        @{ Id='NavValue';       Text=$navMode;}
    )
    $statusBarParts += 
    $part1 = "User: $user | Host: $hostName "
    $part2 = " | DEBUG: "
    $part3 = " | DRY-RUN: "
    $part4 = " | Nav: $navMode"

    $combinedLength = $part1.Length + $part2.Length + $debugText.Length + $part3.Length + $dryRunText.Length + $part4.Length
    try { $width = [Math]::Max(10, [Console]::WindowWidth) } catch { $width = 80 }
    $padLeft = [Math]::Max(0, [int][Math]::Floor(($width - $combinedLength) / 2))
    $padRight = $width - $padLeft - $combinedLength

    Write-Plain (' ' * $padLeft)

    # Write Part 1
    Write-Colored -Text $part1 -Fg $GlobalConfig.InfoColor -Bg $GlobalConfig.BackgroundColor
    $userColor =

    # Write Part 2
    Write-Colored -Text $part2 -Fg $GlobalConfig.InfoColor -Bg $GlobalConfig.BackgroundColor
    $debugColor = if ($debug) { $GlobalConfig.ToggleOnFg } else { $GlobalConfig.MutedColor }
    $debugBg = if ($debug) { $GlobalConfig.ToggleOnBg } else { $GlobalConfig.BackgroundColor }
    Write-Colored -Text $debugText -Fg $debugColor -Bg $debugBg

    # Write Part 3
    Write-Colored -Text $part3 -Fg $GlobalConfig.InfoColor -Bg $GlobalConfig.BackgroundColor
    $dryRunColor = if ($dryRun) { $GlobalConfig.ToggleOnFg } else { $GlobalConfig.MutedColor }
    $dryRunBg = if ($dryRun) { $GlobalConfig.ToggleOnBg } else { $GlobalConfig.BackgroundColor }
    Write-Colored -Text $dryRunText -Fg $dryRunColor -Bg $dryRunBg

    # Write Part 4
    Write-Colored -Text $part4 -Fg $GlobalConfig.InfoColor -Bg $GlobalConfig.BackgroundColor
    Write-Plain (' ' * $padRight)
    [Console]::WriteLine()
}
