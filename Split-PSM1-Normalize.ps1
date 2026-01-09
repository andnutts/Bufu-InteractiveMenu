<#
    .SYNOPSIS
        Interactive .psm1 splitter with PSFzf-aware search and a menu driven by $MenuOptions.
    .DESCRIPTION
        - Search-DirectoryForPsm1: breadth-first, limited-depth search with interactive pick support.
        - Choose-Psm1File: non-recursive scan, then optional filesystem search using Search-DirectoryForPsm1 (PSFzf/Out-GridView/text fallback).
        - Interactive Move: multi-select functions (Invoke-Fzf if available) and write them to Public/Private/Class folders, normalizing scoped declarations.
        - Other utilities: export classes, generate index, remove moved functions (with backup), write helpers.
#>
#==========================================#
#region * Switches and Configuration *
#==========================================#
$DefaultSwitches = @(
    [PSCustomObject]@{ Id = 'N' ; Shortcut = 'N' ; Name = 'Navigation Mode';    State = $navMode;   Type = 'Choice'; Description = 'Toggle Arrow Key or Numeric selection'
        Text    = "Nav: $navMode"
        Value   = $navMode
        TextFg  = $GlobalConfig.InfoColor
        TextBg  = $GlobalConfig.BackgroundColor
        Fg      = if ($navMode -eq 'Arrow') { $GlobalConfig.SelectedTextColor } else { $GlobalConfig.InfoColor }
        Bg      = if ($navMode -eq 'Arrow') { $GlobalConfig.SelectedTextBg } else { $GlobalConfig.BackgroundColor } }
    [PSCustomObject]@{ Id = 'E' ; Shortcut = 'E' ; Name = 'Show Exec Path';     State = $showExec;  Type = 'Toggle'; Description = 'Show/Hide the script execution path'
        Text    = "Path: $showExec"
        Value   = [bool]$showExec
        TextFg  = $GlobalConfig.InfoColor
        TextBg  = $GlobalConfig.BackgroundColor
        Fg      = if ($showExec) { $GlobalConfig.ToggleOnFg } else { $GlobalConfig.MutedColor }
        Bg      = if ($showExec) { $GlobalConfig.ToggleOnBg } else { $GlobalConfig.BackgroundColor } },
    [PSCustomObject]@{ Id = 'D' ; Shortcut = 'D' ; Name = 'Debug Mode';         State = $debug;     Type = 'Toggle'; Description = 'Verbose logging for scripts'
        Text    = "DEBUG: $debugText"
        Value   = [bool]$debug
        TextFg  = $GlobalConfig.InfoColor
        TextBg  = $GlobalConfig.BackgroundColor
        Fg      = if ($debug) { $GlobalConfig.ToggleOnFg } else { $GlobalConfig.MutedColor }
        Bg      = if ($debug) { $GlobalConfig.ToggleOnBg } else { $GlobalConfig.BackgroundColor } },
    [PSCustomObject]@{ Id = 'R' ; Shortcut = 'R' ; Name = 'Dry-Run Mode';       State = $dryRun;    Type = 'Toggle'; Description = 'Prevent actual script execution'
        Text    = "DRY-RUN: $dryRunText"
        Value   = [bool]$dryRun
        TextFg  = $GlobalConfig.InfoColor
        TextBg  = $GlobalConfig.BackgroundColor
        Fg      = if ($dryRun) { $GlobalConfig.ToggleOnFg } else { $GlobalConfig.MutedColor }
        Bg      = if ($dryRun) { $GlobalConfig.ToggleOnBg } else { $GlobalConfig.BackgroundColor } }
)
$GlobalConfig = @{
    # General Status Colors
    SuccessColor          = 'Green'
    WarningColor          = 'Yellow'
    ActionColor           = 'Magenta'
    InfoColor             = 'Cyan'
    ErrorColor            = 'Red'
    MutedColor            = 'DarkGray'
    HighlightColor        = 'White'
    BackgroundColor       = 'Black'
    # Menu Breaks / Decoration
    DividerLength         = 50
    SpaceLineChar         = '='
    SpaceLineColor        = 'DarkCyan'
    SeparatorChar         = '─'
    SeparatorColor        = 'Gray'
    UnderLineChar         = '_'
    UnderLineColor        = 'Gray'
    CornerChar            = '┌'
    BorderColor           = 'DarkGray'
    # Header / Title
    HeaderTitleColor      = 'Green'
    HeaderSubtitleColor   = 'DarkGray'
    HeaderIcon            = '🛠️'
    HeaderPadding         = 2
    HeaderSeparatorChar   = '─'
    HeaderSeparatorColor  = 'Gray'
    # Footer / Usage
    FooterPadding         = 2
    FooterBgColor         = 'Black'
    FooterFgColor         = 'White'
    # Menu item / selection
    SelectedToken         = '->'
    SelectedTokenColor    = 'Black'
    SelectedTokenBg       = 'Yellow'
    SelectedTextColor     = 'White'
    SelectedTextBg        = 'DarkBlue'
    UnselectedTokenColor  = 'Yellow'
    UnselectedTokenBg     = 'Black'
    # Icons / symbols
    SettingIcon           = '⚙️'
    FooterIcon            = 'ℹ️'
    ExitIcon              = '❌'
    CheckedIcon           = '✔'
    UncheckedIcon         = ' '             # space when unchecked
    InfoIcon              = 'ℹ️'
    WarningIcon           = '⚠️'
    SuccessIcon           = '✅'
    # Switches / toggles
    SwitchOnText          = 'ON'
    SwitchOffText         = 'OFF'
    ToggleOnBg            = 'Yellow'
    ToggleOnFg            = 'Black'
    # Behavior / layout
    DefaultMenuMode       = 'Arrow'         # 'Arrow' or 'Numeric'
    MultiSelectDefault    = $false
    WrapNavigation        = $true
    PageSize              = 10
    # Misc
    TimeStampFormat       = 'yyyy-MM-dd HH:mm:ss'
    VerboseEnabled        = $false
}
function Use-GlobalConfig { param([hashtable]$Config) foreach ($k in $Config.Keys) { $gvName = "Global:$k"; Set-Variable -Name $k -Value $Config[$k] -Scope Global -Force } }
#endregion
#==========================================#
#region ----- PRIVATE Functions -----
#==========================================#
#region * Logging Helpers *
#==========================================#
function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet('Info', 'Warning', 'Error', 'Debug')]
        [string]$Level,
        [Parameter(Mandatory=$true)]
        [string]$Message
    )
    $logFile = Get-CurrentLogFile
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "$timestamp [$Level] $Message"
    if (-not (Test-Path $LogDirectory)) {
        New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
    }
    Add-Content -Path $logFile -Value $logEntry -Encoding UTF8
    Cleanup-LogFiles
}
function Get-CurrentLogFile { $datePart = Get-Date -Format "yyyyMMdd"; return Join-Path -Path $LogDirectory -ChildPath "ProfileMenu_$datePart.log" }
function Cleanup-LogFiles {
    $allLogs = Get-ChildItem -Path $LogDirectory -Filter $LogFilePattern | Sort-Object CreationTime -Descending
    #region --- Size Limit Check (optional: can be resource intensive on large directories) ---
    $maxSize = 5MB
    $largeFiles = $allLogs | Where-Object { $_.Length -gt $maxSize } | Sort-Object Length -Descending
    foreach ($file in $largeFiles) {
        Remove-Item -Path $file.FullName -Force -ErrorAction SilentlyContinue
    }
    #endregion
    #region --- Count Limit Check ---
    if ($allLogs.Count -gt $script:MaxLogFiles) {
        $filesToDelete = $allLogs | Select-Object -Skip $script:MaxLogFiles
        foreach ($file in $filesToDelete) {
            Remove-Item -Path $file.FullName -Force -ErrorAction SilentlyContinue
        }
    }
    #endregion
}
#endregion
#==========================================#
#region * Switch and Persistence Handlers *
#==========================================#
function Get-SwitchById { param( [array]$MenuSwitches, [string]$Id ) $MenuSwitches | Where-Object { $_.Id -eq $Id } }
function Set-SwitchState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][array]$MenuSwitches,
        [Parameter(Mandatory)][string]$Id,
        [Parameter()][object]$State
    )
    $s = Get-SwitchById -MenuSwitches $MenuSwitches -Id $Id
    if (-not $s) { throw "Switch '$Id' not found." }
    switch ($s.Type) {
        'Toggle' { $new = if ($PSBoundParameters.ContainsKey('State')) { [bool]$State } else { -not [bool]$s.State } }
        'Choice' { if (-not $PSBoundParameters.ContainsKey('State')) { throw "Must supply -State for Choice type." }; $new = $State }
        default { $new = if ($PSBoundParameters.ContainsKey('State')) { $State } else { -not [bool]$s.State } }
    }
    $s.State = $new
    return $s.State
}
function Save-SwitchStates {
    param([array]$MenuSwitches, [string]$Path)
    if ($Path) { $st = $MenuSwitches | Select-Object Id, State
        try { $st | ConvertTo-Json -Depth 3 | Out-File -FilePath $Path -Encoding UTF8 -Force ;              return $true }
        catch { Write-Host "Warning: Could not save switch states to $Path" -ForegroundColor DarkYellow ;   return $false }
    }
}
function Load-SwitchStates {
    param([array]$MenuSwitches, [string]$Path)
    if ($Path -and (Test-Path $Path)) {
        try { $json = Get-Content -Raw -Path $Path | ConvertFrom-Json
            foreach ($entry in $json) {
                $s = Get-SwitchById -MenuSwitches $MenuSwitches -Id $entry.Id
                if ($s) {
                    if ($s.Type -eq 'Toggle') { $s.State = [bool]$entry.State }
                    else { $s.State = $entry.State }
                }
            }
        } catch { Write-Host "Warning: Could not load switch states from $Path. Using defaults." -ForegroundColor DarkYellow }
    }
    return $MenuSwitches
}
# ------------------------------------------
function Save-Context {
    param([psobject]$Context, [string]$Path = (Join-Path $env:TEMP 'menu-context.json'))
    $Context | ConvertTo-Json -Depth 5 | Set-Content -Path $Path -Encoding UTF8
}
function Load-Context {
    param([string]$Path = (Join-Path $env:TEMP 'menu-context.json'))
    if (Test-Path $Path) { return Get-Content $Path -Raw | ConvertFrom-Json } else { return $null }
}
# ------------------------------------------
#endregion
#==========================================#
#region * Console Helpers *
#==========================================#
function Test-SupportsRawUI { try { return $Host.UI.RawUI.CursorVisible -ne $null -and $Host.UI.RawUI.CanSetCursorPosition } catch { return $false } }
function Hide-Cursor { if (Test-SupportsRawUI) { $Host.UI.RawUI.CursorVisible = $false } }
function Show-Cursor { if (Test-SupportsRawUI) { $Host.UI.RawUI.CursorVisible = $true } }
# ------------------------------------------
function Write-Plain {
    <#
        .SYNOPSIS
            Write text to the console without changing colors.
        .PARAMETER Text
            Text to write. Accepts pipeline input.
    #>
    param([string]$Text)
    [Console]::ResetColor()
    [Console]::Write($Text)
}
function Write-Colored {
    <#
        .SYNOPSIS
            Write text to the console using specified foreground/background colors.
        .PARAMETER Text
            Text to write. Accepts pipeline input.
    #>
    param(
        [string]$Text,
        [ConsoleColor]$Fg = 'White',
        [ConsoleColor]$Bg = 'DarkBlue'
    )
    $origFg = [Console]::ForegroundColor
    $origBg = [Console]::BackgroundColor
    [Console]::ForegroundColor = $Fg
    [Console]::BackgroundColor = $Bg
    [Console]::Write($Text)
    [Console]::ForegroundColor = $origFg
    [Console]::BackgroundColor = $origBg
}
function Show-CenteredLine {
    <#
        .SYNOPSIS
            Display a centered line in the console optionally with a colored token.
        .DESCRIPTION
            Renders text centered in the console window with optional colored tokens and text. Supports multi-line input and pipeline processing.
        .PARAMETER Token
            The token text to display before the main text. Examples include arrows (→, ►), numbers, or any special characters.
            Pass an empty string '' to display no token.
        .PARAMETER TokenColored
            Switch parameter to enable color rendering of the token using TokenFg and TokenBg colors.
        .PARAMETER Text
            The main text content to be centered in the console. Accepts pipeline input and multi-line strings.
            Each line will be centered independently.
        .PARAMETER TokenFg
            The foreground color for the token when TokenColored is enabled.
            Accepts standard PowerShell console colors (e.g., 'White', 'Yellow', 'Cyan').
        .PARAMETER TokenBg
            The background color for the token when TokenColored is enabled.
            Accepts standard PowerShell console colors (e.g., 'Black', 'Blue', 'DarkRed').
        .PARAMETER TextFg
            The foreground color for the main text when TextColored is enabled.
            Accepts standard PowerShell console colors.
        .PARAMETER TextBg
            The background color for the main text when TextColored is enabled.
            Accepts standard PowerShell console colors.
        .PARAMETER TextColored
            Switch parameter to enable color rendering of the main text using TextFg and TextBg colors.
        .EXAMPLE
            Write-CenteredLine -Token '→' -Text 'Processing items...' -TokenColored -TokenFg Yellow
            # Displays a centered line with a yellow arrow token followed by the text
        .EXAMPLE
            'Line 1', 'Line 2' | Write-CenteredLine -Token ''
            # Centers multiple lines without tokens
    #>
    param(
        [string]$Token,              # token text (arrow or numeric label) or '' when nothing
        [bool]$TokenColored,         # token gets colored when $true
        [string]$Text,               # main item text
        [ConsoleColor]$TokenFg = 'Yellow',
        [ConsoleColor]$TokenBg = 'DarkBlue',
        [ConsoleColor]$TextFg = 'White',
        [ConsoleColor]$TextBg = 'DarkBlue',
        [bool]$TextColored = $false
    )
    begin {
        try { $width = [Math]::Max(10, [Console]::WindowWidth) } catch { $width = 80 }
    }
    process {
        if ($null -eq $Text) { return }
        $lines = $Text -split "`r?`n"
        foreach ($line in $lines) {
            $displayText = if ($line.Length -gt $width) { $line.Substring(0, $width) } else { $line }
            $combined = ($Token + $(if ($Token) { ' ' } else { '' }) + $displayText).TrimEnd()
            $padLeft = [Math]::Max(0, [int][Math]::Floor(($width - $combined.Length) / 2))
            $padRight = $width - $padLeft - $combined.Length
            Write-Plain (' ' * $padLeft)
            if ($Token) {
                if ($TokenColored) { Write-Colored -Text $Token -Fg $TokenFg -Bg $TokenBg }
                else { Write-Plain $Token }
                if ($displayText) { Write-Plain ' ' }
            }
            if ($TextColored) { Write-Colored -Text $displayText -Fg $TextFg -Bg $TextBg }
            else { Write-Plain $displayText }
            Write-Plain (' ' * $padRight)
            [Console]::WriteLine()
        }
    }
}
#endregion
#==========================================#
#region * Build Menu *
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
function Show-Header {
    <#
      .SYNOPSIS
        Clears the screen and displays a centered, colored banner header.
      .DESCRIPTION
        Derives a title with Get-MenuTitle when one is not supplied, prints an optional subtitle,
        and draws decorative spacer/underline lines using values from $GlobalConfig.
      .PARAMETER Title
        Optional title text. If omitted, Get-MenuTitle -Path $ScriptDir is used.
      .PARAMETER Subtitle
        Optional subtitle text displayed under the title.
      .PARAMETER ScriptDir
        Required script directory or path used to derive a title when -Title is omitted.
      .PARAMETER MenuSwitches
        Optional array of menu switches (passed through only if needed by helpers).
    #>
    param(
        [Parameter(Mandatory=$false)][string]$Title,
        [Parameter(Mandatory=$false)][string]$Subtitle,
        [Parameter(Mandatory=$true)][string]$ScriptDir,
        [Parameter(Mandatory=$false)][array]$MenuSwitches = @()
    )
    if (-not $Title) {
        try { $derived = Get-MenuTitle -Path $ScriptDir
            if ($derived) { $Title = $derived } else { $Title = Split-Path -Leaf $ScriptDir }
        } catch { $Title = Split-Path -Leaf $ScriptDir }
    }
    $pad            = if ($GlobalConfig.HeaderPadding) { [int]$GlobalConfig.HeaderPadding } else { 2 }
    $sepChar        = if ($GlobalConfig.SeparatorChar) { $GlobalConfig.SeparatorChar } else { '─' }
    $spacelineChar  = if ($GlobalConfig.SpaceLineChar) { $GlobalConfig.SpaceLineChar } else { '=' }

    $lineLength = [Math]::Max(10, ($Title.Length + ($pad * 2)))
    $spaceline = ($spacelineChar * $lineLength)
    $underline  = ($sepChar * $lineLength)

    Show-CenteredLine -Token '' -TokenColored:$false -Text $Title     -TextColored:$false -TextFg $GlobalConfig.HeaderTitleColor
    Show-CenteredLine -Token '' -TokenColored:$false -Text $spaceline -TextColored:$false -TextFg $GlobalConfig.SpaceLineColor
    if ($Subtitle) {
        Show-CenteredLine -Token '' -TokenColored:$false -Text $Subtitle   -TextColored:$false -TextFg $GlobalConfig.HeaderSubtitleColor
        Show-CenteredLine -Token '' -TokenColored:$false -Text $underline  -TextColored:$false -TextFg $GlobalConfig.SeparatorColor
    } else {
        Show-CenteredLine -Token '' -TokenColored:$false -Text $underline  -TextColored:$false -TextFg $GlobalConfig.SeparatorColor
    }
    Write-Host ""
}
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
    try { $showExecPath = [bool](Get-SwitchById -MenuSwitches $MenuSwitches -Id 'E').State   } catch { $showExecPath  = $true }
    $debugText  = if ($debug)   { $GlobalConfig.SwitchOnText } else { $GlobalConfig.SwitchOffText }
    $dryRunText = if ($dryRun)  { $GlobalConfig.SwitchOnText } else { $GlobalConfig.SwitchOffText }
    $navMode    = if ($navMode -eq 'Arrow') { 'Arrow' } else { 'Numeric' }
    $user = [Environment]::UserName
    $hostName = $env:COMPUTERNAME
    $statDisplay = "[User: $user | Host: $hostName | DEBUG: $debugText | DRY-RUN: $dryRunText | Nav: $navMode]"

    if ($showExecPath) {
        Show-CenteredLine -Token '' -TokenColored:$false -Text ("Execution path: $ScriptDir") -TextColored:$false -TextFg $GlobalConfig.InfoColor
    }
    Show-CenteredLine -Token '' -TokenColored:$false -Text $statDisplay -TextColored:$false -TextFg $GlobalConfig.InfoColor
    Write-Host ''
}
function Show-Footer {
    <#
      .SYNOPSIS
        Displays the menu footer / usage text centered.
      .DESCRIPTION
        Uses the provided Mode and MenuItems to build context-sensitive help text.
      .PARAMETER Mode
        Navigation mode: 'Arrow' or 'Numeric'.
      .PARAMETER MenuItems
        Array of menu item objects (only Count used).
      .PARAMETER MenuSwitches
        Optional switches array for keys list.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Mode,
        [Parameter(Mandatory=$true)][array]$MenuItems,
        [Parameter(Mandatory=$false)][array]$MenuSwitches = @()
    )
    $numItems = if ($null -ne $MenuItems) { $MenuItems.Count } else { 0 }
    $switchHints = "Switches: [D]ebug, [N]av, [R]un, [E]xecPath"
    if ($Mode -eq 'Arrow') {
        $footerText = "Use Arrow Keys (Up/Down) to move, [Enter] to run, [Space] to select (multi-select), Q/ESC to quit. $switchHints"
    } else {
        $footerText = "Press number (1-$numItems) to run immediately, [Space] to toggle (multi-select), Q/ESC to quit. $switchHints"
    }
    $pad = if ($GlobalConfig.FooterPadding) { [int]$GlobalConfig.FooterPadding } else { 2 }
    $sepChar        = if ($GlobalConfig.SeparatorChar) { $GlobalConfig.SeparatorChar } else { '─' }
    $spacelineChar  = if ($GlobalConfig.SpaceLineChar) { $GlobalConfig.SpaceLineChar } else { '=' }
    $underlineChar  = if ($GlobalConfig.UnderLineChar) { $GlobalConfig.UnderLineChar } else { '_' }

    $lineLength = [Math]::Max(10, ($footerText.Length + ($pad * 2)))
    $spaceline = ($spacelineChar * $lineLength)
    $underline = ($underlineChar * [Math]::Min(80, [Math]::Max(10, $footerText.Length)))

    Show-CenteredLine -Token '' -TokenColored:$false -Text $spaceline -TextColored:$false -TextFg $GlobalConfig.SpaceLineColor
    Show-CenteredLine -Token '' -TokenColored:$false -Text $footerText -TextColored:$false -TextFg $GlobalConfig.FooterFgColor

    Show-CenteredLine -Token '' -TokenColored:$false -Text $underline -TextColored:$false -TextFg $GlobalConfig.UnderLineColor
    Show-CenteredLine -Token '' -TokenColored:$false -Text $footerText -TextColored:$false -TextFg $GlobalConfig.MutedColor
    Write-Host ''
}
#endregion
#==========================================#
#region * Key Input Handler *
#==========================================#
function Get-MenuKeyAction {
    <#
      .SYNOPSIS
        Capture a single key press and convert it into a normalized menu action.
      .DESCRIPTION
        Uses the ConsoleKey ($key.Key) for matching. Handles arrows, Enter/Space,
        Home/End/PageUp/PageDown, digits (top row and numpad) mapped to Jump,
        printable letters (returned as Letter with uppercase value), Ctrl+C -> Exit.
        When -MultiSelect is $true the Spacebar returns Action = 'Toggle' so the caller
        can add/remove the current SelectedIndex from a selection set.
      .PARAMETER OptionsCount
        Total number of menu options (used for wrapping and numeric jumps). Default 0.
      .PARAMETER SelectedIndex
        Current selected index (0-based). Default 0.
      .PARAMETER MultiSelect
        When present/true, Spacebar will return Action = 'Toggle' instead of 'Enter'.
      .PARAMETER OnEnter
        Optional scriptblock invoked when Enter is pressed. Receives the SelectedIndex.
      .PARAMETER OnExit
        Optional scriptblock invoked when Exit is requested.
      .OUTPUTS
        PSCustomObject with keys: Action, SelectedIndex, RawKey, KeyName, Char, Letter (when Action = 'Letter').
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)][int]$OptionsCount = 0,
        [Parameter(Mandatory = $false)][int]$SelectedIndex = 0,
        [Parameter(Mandatory = $false)][switch]$MultiSelect,
        [Parameter(Mandatory = $false)][ScriptBlock]$OnEnter,
        [Parameter(Mandatory = $false)][ScriptBlock]$OnExit
    )
    $raw = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    $keyName = $raw.Key.ToString()
    $ch = if ($raw.Character -and $raw.Character -ne [char]0) { $raw.Character } else { '' }
    if ($raw.ControlKeyState -band [System.ConsoleModifiers]::Control -and ($raw.Character -eq [char]3)) {
        if ($OnExit) { & $OnExit.Invoke() }
        return [PSCustomObject]@{
            Action        = 'Exit'
            SelectedIndex = $SelectedIndex
            RawKey        = $raw
            KeyName       = $keyName
            Char          = $ch
        }
    }
    switch ($keyName) {
        'Enter' {
            if ($OnEnter) { & $OnEnter.Invoke($SelectedIndex) }
            return [PSCustomObject]@{
                Action        = 'Enter'
                SelectedIndex = $SelectedIndex
                RawKey        = $raw
                KeyName       = $keyName
                Char          = $ch
            }
        }
        'Spacebar' {
            if ($MultiSelect) {
                return [PSCustomObject]@{
                    Action        = 'Toggle'
                    SelectedIndex = $SelectedIndex
                    RawKey        = $raw
                    KeyName       = $keyName
                    Char          = $ch
                }
            } else {
                if ($OnEnter) { & $OnEnter.Invoke($SelectedIndex) }
                return [PSCustomObject]@{
                    Action        = 'Enter'
                    SelectedIndex = $SelectedIndex
                    RawKey        = $raw
                    KeyName       = $keyName
                    Char          = $ch
                }
            }
        }
        'Escape' {
            if ($OnExit) { & $OnExit.Invoke() }
            return [PSCustomObject]@{
                Action        = 'Exit'
                SelectedIndex = $SelectedIndex
                RawKey        = $raw
                KeyName       = $keyName
                Char          = $ch
            }
        }
        'Home' {
            return [PSCustomObject]@{
                Action        = 'Jump'
                SelectedIndex = 0
                RawKey        = $raw
                KeyName       = $keyName
                Char          = $ch
            }
        }
        'End' {
            $last = [Math]::Max(0, $OptionsCount - 1)
            return [PSCustomObject]@{
                Action        = 'Jump'
                SelectedIndex = $last
                RawKey        = $raw
                KeyName       = $keyName
                Char          = $ch
            }
        }
        'PageUp' {
            $new = [System.Math]::Max(0, $SelectedIndex - 10)
            return [PSCustomObject]@{
                Action        = 'Jump'
                SelectedIndex = $new
                RawKey        = $raw
                KeyName       = $keyName
                Char          = $ch
            }
        }
        'PageDown' {
            $new = [System.Math]::Min([Math]::Max(0, $OptionsCount - 1), $SelectedIndex + 10)
            return [PSCustomObject]@{
                Action        = 'Jump'
                SelectedIndex = $new
                RawKey        = $raw
                KeyName       = $keyName
                Char          = $ch
            }
        }
        'UpArrow' {
            if ($OptionsCount -gt 0) {
                $new = $SelectedIndex - 1
                if ($new -lt 0) { $new = $OptionsCount - 1 }
            } else { $new = $SelectedIndex }
            return [PSCustomObject]@{
                Action        = 'Up'
                SelectedIndex = $new
                RawKey        = $raw
                KeyName       = $keyName
                Char          = $ch
            }
        }
        'DownArrow' {
            if ($OptionsCount -gt 0) {
                $new = $SelectedIndex + 1
                if ($new -ge $OptionsCount) { $new = 0 }
            } else { $new = $SelectedIndex }
            return [PSCustomObject]@{
                Action        = 'Down'
                SelectedIndex = $new
                RawKey        = $raw
                KeyName       = $keyName
                Char          = $ch
            }
        }
    }
    if ($keyName -match '^D([0-9])$' -or $keyName -match '^NumPad([0-9])$') {
        $m = [regex]::Match($keyName, '\d')
        if ($m.Success) {
            $digit = [int]$m.Value
            if ($digit -gt 0 -and $digit -le $OptionsCount) {
                return [PSCustomObject]@{
                    Action        = 'Jump'
                    SelectedIndex = $digit - 1
                    RawKey        = $raw
                    KeyName       = $keyName
                    Char          = $ch
                }
            } else {
                return [PSCustomObject]@{
                    Action        = 'NoOp'
                    SelectedIndex = $SelectedIndex
                    RawKey        = $raw
                    KeyName       = $keyName
                    Char          = $ch
                }
            }
        }
    }
    if ($ch) {
        try { $letter = $ch.ToString().ToUpperInvariant() } catch { $letter = $ch }
        return [PSCustomObject]@{
            Action        = 'Letter'
            SelectedIndex = $SelectedIndex
            RawKey        = $raw
            KeyName       = $keyName
            Char          = $ch
            Letter        = $letter
        }
    }
    return [PSCustomObject]@{
        Action        = 'NoOp'
        SelectedIndex = $SelectedIndex
        RawKey        = $raw
        KeyName       = $keyName
        Char          = $ch
    }
}
function Read-MenuKey {
    param(
        [Parameter(Mandatory)][array]$MenuSwitches,
        [Parameter(Mandatory)][ValidateSet('Arrow','Numeric')][string]$Mode
    )
    $raw = [System.Console]::ReadKey($true)
    $char = ''
    try { $char = $raw.KeyChar.ToString() } catch { $char = '' }
    $intent = 'Other'
    $switchId = $null
    $number = $null
    switch ($raw.Key) {
        'UpArrow'    { $intent = 'Up' }
        'DownArrow'  { $intent = 'Down' }
        'Enter'      { $intent = 'Enter' }
        'Escape'     { $intent = 'Escape' }
        'Q'          { $intent = 'Quit' }
        default      { }
    }
    if ($char) {
        $u = $char.ToUpper()
        if ($MenuSwitches -and ($MenuSwitches | Where-Object Id -EQ $u)) {
            $intent = 'Switch'
            $switchId = $u
        }
        if ($Mode -eq 'Numeric' -and $char -match '^\d$' -and $intent -ne 'Switch') {
            $n = [int]$char
            if ($n -ge 1) {
                $intent = 'Number'
                $number = $n
            }
        }
    }
    return [PSCustomObject]@{
        Key        = $raw.Key
        KeyChar    = $char
        Intent     = $intent
        SwitchId   = $switchId
        Number     = $number
        RawKeyInfo = $raw
    }
}
#endregion
#==========================================#
#region * Menu Renderer & Helper *
#==========================================#
function Render-FullMenu {
    param(
        [int]$Selected,
        [string]$Mode,
        [array]$MenuSwitches,
        [array]$MenuItems,
        [string]$Title,
        [string]$ScriptDir
    )
    try { Clear-Host } catch { [Console]::Clear() }
    Show-Header -Title $Title -ScriptDir $ScriptDir -MenuSwitches $MenuSwitches
    Show-StatusBar -ScriptDir $ScriptDir -MenuSwitches $MenuSwitches
    foreach ($s in $MenuSwitches) {
        $label = "[{0}] {1}" -f $s.Id, $s.Name
        $stateText = if ($s.Type -eq 'Toggle') { if ($s.State) { 'ON' } else { 'OFF' } } else { $s.State }
        $combined = "$label : $stateText"
        try { $width = [Math]::Max(10, [Console]::WindowWidth) } catch { $width = 80 }
        $display = if ($combined.Length -gt $width) { $combined.Substring(0, $width) } else { $combined }
        $padLeft = [Math]::Max(0, [int][Math]::Floor(($width - $display.Length) / 2))
        $padRight = $width - $padLeft - $display.Length
        Write-Plain (' ' * $padLeft)
        $idx = $display.IndexOf($stateText)
        if ($idx -gt 0) {
            $before = $display.Substring(0, $idx)
            $after = $display.Substring($idx + $stateText.Length)
            Write-Plain $before
            if ($s.Type -eq 'Toggle' -and $s.State) {
                Write-Colored -Text $stateText -Fg 'Black' -Bg 'Yellow'
            } else {
                Write-Plain $stateText
            }
            Write-Plain $after
        } else {
            Write-Plain $display
        }
        Write-Plain (' ' * $padRight)
        [Console]::WriteLine()
    }
    Show-CenteredLine -Token '' -TokenColored:$false -Text ('─' * 40) -TextColored:$false -TextFg 'Gray'
    for ($i = 0; $i -lt $MenuItems.Count; $i++) {
        $itemName = $MenuItems[$i].Name

        if ($Mode -eq 'Arrow') {
            $indicator = if ($i -eq $Selected) { '->' } else { ' ' }
            $fg = if ($i -eq $Selected) { 'White' } else { 'White' }
            $bg = if ($i -eq $Selected) { 'DarkBlue' } else { 'Black' }

            if ($i -eq $Selected) {
                Show-CenteredLine -Token '->' -TokenColored:$true -Text $itemName -TokenFg 'Black' -TokenBg 'Yellow' -TextFg $fg -TextBg $bg -TextColored:$true
            } else {
                Show-CenteredLine -Token ' ' -TokenColored:$false -Text (" $($itemName)") -TextColored:$false -TextFg 'White'
            }
        } else {
            $label = ('{0}:' -f ($i + 1)).PadRight(3)
            $fg = if ($i -eq $Selected) { 'White' } else { 'White' }
            $bg = if ($i -eq $Selected) { 'DarkBlue' } else { 'Black' }

            if ($i -eq $Selected) {
                Show-CenteredLine -Token $label -TokenColored:$true -Text $itemName -TokenFg 'Black' -TokenBg 'Yellow' -TextFg $fg -TextBg $bg -TextColored:$true
            } else {
                Show-CenteredLine -Token $label -TokenColored:$true -Text $itemName -TokenFg 'Yellow' -TokenBg 'Black' -TextColored:$false -TextFg 'White'
            }
        }
    }
    Show-CenteredLine -Token '' -TokenColored:$false -Text ('-' * 45) -TextColored:$false -TextFg 'Gray'
    Show-Footer -Mode $Mode -MenuItems $MenuItems -MenuSwitches $MenuSwitches
}
function Invoke-MenuEntry {
    param(
        [Parameter(Mandatory)][object]$Entry,
        [Parameter(Mandatory)][string]$ScriptDir,
        [Parameter(Mandatory)][array]$MenuSwitches
    )
    $debugFlag = (Get-SwitchById -MenuSwitches $MenuSwitches -Id 'D').State
    $dryRunFlag = (Get-SwitchById -MenuSwitches $MenuSwitches -Id 'R').State

    if ($dryRunFlag) {
        Write-Host "DRY RUN MODE: Command not executed." -ForegroundColor Yellow
        # Check if it's a file entry or action entry for logging
        if ($Entry.PSObject.Properties['File']) {
            Write-Host "Target: $($Entry.File) (Type: $($Entry.Type))`n" -ForegroundColor Yellow
        } elseif ($Entry.PSObject.Properties['Action']) {
            Write-Host "Action: $($Entry.Name)`n" -ForegroundColor Yellow
        }
        return $true
    }

    # --- Check for ScriptBlock Action ---
    if ($Entry.PSObject.Properties['Action'] -and $Entry.Action -is [ScriptBlock]) {
        Write-Host "`n[Running: $($Entry.Name)...]`n" -ForegroundColor Yellow
        try {
            # Invoke the scriptblock. Pass MenuSwitches as an argument for context if needed,
            # or just invoke directly.
            $result = & $Entry.Action.Invoke()
            # Check for 'quit' signal from scriptblock
            if ($result -eq 'quit') {
                return 'quit' # Propagate quit signal
            }
            return $true
        } catch {
            Write-Colored -Text "`nERROR during action '$($Entry.Name)': $($_.Exception.Message)`n" -Fg 'White' -Bg 'DarkRed'
            return $false
        }
    }

    # --- Existing File-based logic ---
    if (-not $Entry.PSObject.Properties['File']) {
        Write-Warning "Menu entry '$($Entry.Name)' has no 'Action' or 'File' defined."
        return $false
    }

    $scriptPath = Join-Path -Path $ScriptDir -ChildPath $Entry.File
    if (-not (Test-Path $scriptPath)) {
        Write-Colored -Text "Script not found: $scriptPath`n" -Fg 'White' -Bg 'DarkRed'
        return $false
    }

    Write-Host "`n[Running: $($Entry.Name)...]`n" -ForegroundColor Yellow

    switch ($Entry.Type) {
        'GUI' {
            Write-Host "Starting GUI script in new process..." -ForegroundColor DarkCyan
            Start-Process -FilePath "python" -ArgumentList @($scriptPath) -ErrorAction SilentlyContinue
        }
        'CMD' {
            Write-Host "Executing CMD script inline..." -ForegroundColor DarkCyan
            $argList = @($scriptPath)
            if ($debugFlag) { $argList += '--verbose' }
            & python @argList
        }
        'PS1' {
            Write-Host "Executing PowerShell script inline..." -ForegroundColor DarkCyan
            . $scriptPath
        }
        default {
            Write-Host "Starting generic process..." -ForegroundColor DarkCyan
            Start-Process -FilePath "python" -ArgumentList @($scriptPath) -ErrorAction SilentlyContinue
        }
    }
    return $true
}
#endregion
#==========================================#
#region * Function Helpers *
#==========================================#
function Read-Path {
    [OutputType([string])]
    param(
        [string]$Message,
        [string]$DefaultPath = $global:LastPath
    )
    if ([string]::IsNullOrWhiteSpace($DefaultPath)) { $DefaultPath = (Get-Location).Path }
    while ($true) {
        $inputPath = Read-Host -Prompt "$Message (Default: '$DefaultPath')"
        if ([string]::IsNullOrWhiteSpace($inputPath)) { $inputPath = $DefaultPath }
        if ($inputPath -match '^\$[A-Za-z_]\w*') { Write-ColoredText "Invalid variable reference." -ForegroundColor Red; continue }
        if (Test-Path -Path $inputPath) { $global:LastPath = $inputPath; return $inputPath }
        else { Write-Color -Message "Path not found. Please try again." -ForegroundColor $Theme.PromptErrorColor }
    }
}
function Prompt-ChooseFile {
    param(
        [string]$Message = 'Choose a .psm1 file',
        [bool]$AllowFilesystemSearch = $true,
        [ScriptBlock]$PromptFunction = $null
    )

    if (-not $PromptFunction) {
        $PromptFunction = {
            param($m,$a)
            if (Get-Command Out-GridView -ErrorAction SilentlyContinue) {
                Get-ChildItem -Path (Get-Location) -Filter '*.psm1' -Recurse -ErrorAction SilentlyContinue |
                    Select-Object -ExpandProperty FullName | Out-GridView -Title $m -PassThru
            } else {
                Read-Host "$m`n(enter full path or blank to cancel)"
            }
        }
    }

    return & $PromptFunction $Message $AllowFilesystemSearch
}
function Confirm-YesNo {
    param(
        [string]$Message = 'Proceed?',
        [ScriptBlock]$ConfirmFunction = $null
    )

    if (-not $ConfirmFunction) {
        $ConfirmFunction = { param($m) (Read-Host "$m (y/N)") -match '^(y|Y)' }
    }

    return & $ConfirmFunction $Message
}
#endregion
#==========================================#
#endregion
#==========================================#

#==========================================#
#region ----- Script Functions -----
#==========================================#
#region * Context Helpers *
#==========================================#
function Load-AstAndSource-Context {
    param(
        [Parameter(Mandatory)][psobject]$Context,
        [string]$Path
    )

    # do parsing / dot-sourcing while avoiding hidden global writes
    # (this example assumes Load-AstAndSource original returns parsed objects)
    $parsed = Load-AstAndSource -Path $Path    # reuse existing implementation (side-effects internal to module load)
    # if original Load-AstAndSource mutates environment (e.g., defines functions), you may keep that, but state is recorded in Context
    $Context.Parts = $parsed
    return $Context
}
function Ensure-OutDirs-Context {
    param(
        [Parameter(Mandatory)][psobject]$Context,
        [string]$BaseOut
    )

    if (-not $BaseOut) { throw 'BaseOut required' }
    if (-not (Test-Path $BaseOut)) { New-Item -Path $BaseOut -ItemType Directory -Force | Out-Null }

    # create canonical subfolders you expect
    $dirs = @('Classes','Functions','Private')
    foreach ($d in $dirs) {
        $p = Join-Path $BaseOut $d
        if (-not (Test-Path $p)) { New-Item -Path $p -ItemType Directory -Force | Out-Null }
    }

    $Context.OutDir = $BaseOut
    return $Context
}
function Choose-Psm1File-Context {
    param(
        [Parameter(Mandatory)] [psobject] $Context,
        [bool] $AllowFilesystemSearch = $true,
        [ScriptBlock] $PromptFunction = $null
    )
    if (-not $PromptFunction) { $PromptFunction = { param($m,$a) Prompt-ChooseFile -Message $m -AllowFilesytemSearch $a } }
    $selected = & $PromptFunction 'Select a .psm1 to load' $AllowFilesystemSearch
    if (-not $selected) {
        return $Context
    }
    $Context.Psm1Path = $selected
    if (-not $Context.OutDir) {
        $base = (Split-Path -Leaf $selected) -replace '\.psm1$',''
        $Context.OutDir = Join-Path -Path (Split-Path -Parent $selected) -ChildPath ("$base-Split")
    }
    return $Context
}
#endregion
#==========================================#
#region * Action Registry *
#==========================================#
$ActionRegistry = @{}
function Register-Action {
    param([string]$Id, [ScriptBlock]$Script)
    if (-not $Id) { throw 'Id required' }
    $ActionRegistry[$Id] = $Script
}
# Default rehydration mapping: map well-known globals into Context keys
$DefaultRehydrateMap = @{
    'Psm1Path'   = { if (Get-Variable -Name 'Psm1Path' -Scope Script -ErrorAction SilentlyContinue) { (Get-Variable -Name 'Psm1Path' -Scope Script).Value } elseif (Get-Variable -Name 'Psm1Path' -Scope Global -ErrorAction SilentlyContinue) { (Get-Variable -Name 'Psm1Path' -Scope Global).Value } else { $null } }
    'OutDir'     = { if (Get-Variable -Name 'GlobalConfig' -Scope Script -ErrorAction SilentlyContinue) { $g=(Get-Variable -Name 'GlobalConfig' -Scope Script).Value; if ($g -and $g.OutDir) { $g.OutDir } else { $null } } elseif (Get-Variable -Name 'GlobalConfig' -Scope Global -ErrorAction SilentlyContinue) { $g=(Get-Variable -Name 'GlobalConfig' -Scope Global).Value; if ($g -and $g.OutDir) { $g.OutDir } else { $null } } else { $null } }
    'LastUsed'   = { (Get-Date) }
}
# Invoke-ActionById: compatible wrapper
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
#endregion
#==========================================#
#region * Helpers *
#==========================================#
function Load-AstAndSource {
    param([string]$Path)
    Write-Host "Loading AST and source for: $Path"
    # Simplified simulation of AST loading and function/class parsing
    # In a real script, this would parse the PSM1 file to populate $GlobalConfig
    $GlobalConfig.PSM1Path = $Path
    $GlobalConfig.OutDir = Join-Path (Split-Path -Parent $Path) "$((Split-Path -Leaf $Path) -replace '\.psm1$','')-Split"
    Write-Host "Output directory set to: $($GlobalConfig.OutDir)"
}
function Choose-Psm1File {
    param(
        [string]$StartDir = (Get-Location),
        [switch]$AllowFilesystemSearch
    )

    $psm1s = Get-ChildItem -Path $StartDir -Filter *.psm1 -File -ErrorAction SilentlyContinue
    if ($psm1s -and $psm1s.Count -gt 0) {
        if ($psm1s.Count -eq 1) { return $psm1s[0].FullName }
        for ($i = 0; $i -lt $psm1s.Count; $i++) { Write-Host ("[{0}] {1}" -f ($i+1), $psm1s[$i].Name) }
        $choice = Read-Host "Enter number of file to use (or leave empty to cancel or press S to search filesystem)"
        if (-not $choice) { return $null }
        if ($choice -match '^[sS]$') {
            $AllowFilesystemSearch = $true
        } elseif ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $psm1s.Count) {
            return $psm1s[[int]$choice - 1].FullName
        } else {
            Write-Warning "Invalid selection."
            return $null
        }
    }

    if (-not $AllowFilesystemSearch) {
        $yn = Read-Host "No .psm1 found in $StartDir. Search filesystem for .psm1 files? (y/n) [y]"
        if (-not $yn) { $yn = 'y' }
        if ($yn -notmatch '^(y|Y)') { return $null }
    }

    try {
        $home = $env:USERPROFILE
        if (-not $home) { $home = [Environment]::GetFolderPath('UserProfile') }
        $found = Search-DirectoryForPsm1 -Path $home -Recurse -MaxDepth 6 -SkipDirs @('.git','node_modules','bin','obj') -IncludeHidden:$false -Pick -UseFzfIfAvailable
        if ($found -and ($found -is [System.IO.FileInfo])) { return $found.FullName }
        if ($found -and ($found -is [System.String])) { return $found }
        if ($found -and ($found.Count -gt 0)) { return $found[0].FullName }
        Write-Warning "No .psm1 files found by filesystem search."
        return $null
    } catch {
        Write-Warning "Filesystem search failed: $($_.Exception.Message)"
        $manual = Read-Host "Enter full path to a .psm1 file or leave empty to cancel"
        if ($manual -and (Test-Path $manual)) { return (Resolve-Path $manual).Path }
        return $null
    }
}
function Interactive-MoveFunctions {
    if (-not $script:FunctionAsts -or $script:FunctionAsts.Count -eq 0) { Write-Host "No functions to move."; return }
    $display = $script:FunctionAsts | ForEach-Object { ($_.Extent.Text -split "`r?`n",2)[0].Trim() }
    $selected = Select-Multi -Items $display -Prompt "Select functions to move"
    if (-not $selected -or $selected.Count -eq 0) { Write-Host "No selection."; return }
    $selectedAsts = @()
    foreach ($s in $selected) { $selectedAsts += ($script:FunctionAsts | Where-Object { ($_.Extent.Text -split "`r?`n",2)[0].Trim() -eq $s } | Select-Object -First 1).Extent }
    $applyAll = $true
    $ans = Read-Host "Apply same destination to all? (y/n) [y]"; if (-not $ans) { $ans='y' }; if ($ans -notmatch '^(y|Y)') { $applyAll = $false }
    $destMap = @{}
    if ($applyAll) {
        $dest = Read-Host "Destination (Public / Private / Class) [Private]"; if (-not $dest) { $dest='Private' }
        foreach ($ast in $selectedAsts) { $destMap[$ast.StartOffset] = $dest }
    } else {
        foreach ($ast in $selectedAsts) {
            $preview = ($ast.Text -split "`r?`n",2)[0].Trim()
            $d = Read-Host "Destination for '$preview' (Public / Private / Class) [Private]"; if (-not $d) { $d='Private' }
            $destMap[$ast.StartOffset] = $d
        }
    }
    foreach ($ast in $selectedAsts) {
        $raw = $ast.Text; $norm = Normalize-FunctionText -rawText $raw
        $name = if ($norm -match 'function\s+([^\s{(]+)') { $matches[1] } else { "Function_$($ast.StartLine)" }
        $safeName = $name -replace '[\\/:*?"<>| ]','_'
        $dir = switch ($destMap[$ast.StartOffset].ToLower()) { 'public' { $script:PublicDir } 'class' { $script:ClassDir } default { $script:PrivateDir } }
        $out = Join-Path $dir ("$safeName.ps1")
        $norm.Trim() | Set-Content -Path $out -Encoding UTF8
        Write-Host "Wrote $out"
    }
    Load-AstAndSource -Path $Psm1Path
}
function Export-AllClasses {
    if (-not $script:ClassAsts -or $script:ClassAsts.Count -eq 0) { Write-Host "No classes present."; return }
    foreach ($c in $script:ClassAsts) {
        $name = $c.Name -replace '[\\/:*?"<>| ]','_'
        $out = Join-Path $script:ClassDir ("$name.ps1")
        $c.Extent.Text.Trim() | Set-Content -Path $out -Encoding UTF8
        Write-Host "Wrote $out"
    }
}
function Generate-Index {
    $publicFiles = Get-ChildItem -Path $script:PublicDir -Filter *.ps1 -File -ErrorAction SilentlyContinue
    if (-not $publicFiles) { Write-Host "No Public files to index."; return }
    $lines = @()
    foreach ($p in $publicFiles) {
        $lines += ". `$PSScriptRoot\Public\$($p.Name)"
    }
    $indexPath = Join-Path $OutDir (Split-Path -Leaf $Psm1Path -replace '\.psm1$','.psm1')
    $lines | Set-Content -Path $indexPath -Encoding UTF8
    Write-Host "Wrote index module: $indexPath"
}
function Write-Helpers {
    $usedSpans = New-Object System.Collections.Generic.List[System.Management.Automation.Language.TextRange]
    foreach ($f in $script:FunctionAsts) { $usedSpans.Add($f.Extent) }
    foreach ($c in $script:ClassAsts) { $usedSpans.Add($c.Extent) }
    $lines = $script:Source -split "`r?`n"
    $keep = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $lines.Length; $i++) {
        $lineNum = $i + 1; $inside = $false
        foreach ($u in $usedSpans) { if ($lineNum -ge $u.StartLine -and $lineNum -le $u.EndLine) { $inside = $true; break } }
        if (-not $inside) { $keep.Add($lines[$i]) }
    }
    $helpersText = $keep -join "`r`n"
    if ($helpersText.Trim()) {
        $hPath = Join-Path $script:PrivateDir '_helpers.ps1'
        $helpersText.Trim() | Set-Content -Path $hPath -Encoding UTF8
        Write-Host "Wrote $hPath"
    } else { Write-Host "No helper content to write." }
}
function Remove-MovedFromSource {
    <#
        .SYNOPSIS
            Removes functions and classes from the source .psm1 file that
            have been extracted to the Public/Private/Class directories.
        .DESCRIPTION
            This function is much safer than the regex-based original.
            1. Creates a backup of the source file.
            2. Scans Public, Private, and Class folders for .ps1 files.
            3. Gets the base name (e.g., 'MyFunction') from each file.
            4. Finds all Function and Class AST nodes in the loaded module
               that match these names.
            5. Gathers the 'Extent' (start/end line) for each matched AST node.
            6. Re-builds the source file by keeping only the lines that are
               *outside* the extents of the moved items.
            7. Overwrites the original .psm1 and re-loads the AST.
    #>
    $bak = "$Psm1Path.bak.$((Get-Date).ToString('yyyyMMddHHmmss'))"
    Copy-Item -Path $Psm1Path -Destination $bak -Force
    Write-Host "Backup created: $bak"

    # 1. Get all files/names that have been moved
    $allMovedFiles = Get-ChildItem -Path $script:PublicDir,$script:PrivateDir,$script:ClassDir -Filter *.ps1 -File -ErrorAction SilentlyContinue
    if (-not $allMovedFiles) { Write-Host "No moved files found to remove from source."; return }
    $movedNames = $allMovedFiles | ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Name) } | Select-Object -Unique

    # 2. Find all Function/Class AST nodes that match these names
    $astsToRemove = New-Object System.Collections.Generic.List[System.Management.Automation.Language.Ast]
    foreach ($name in $movedNames) {
        # Find functions
        $astsToRemove.AddRange( ($script:FunctionAsts | Where-Object { $_.Name -eq $name }) )
        # Find classes
        $astsToRemove.AddRange( ($script:ClassAsts | Where-Object { $_.Name -eq $name }) )
    }

    if ($astsToRemove.Count -eq 0) {
        Write-Warning "Found moved files, but couldn't match them to AST nodes in the source. No changes made."
        return
    }

    # 3. Get the extents (text ranges) of these AST nodes
    $usedSpans = New-Object System.Collections.Generic.List[System.Management.Automation.Language.TextRange]
    foreach ($ast in $astsToRemove) { $usedSpans.Add($ast.Extent) }

    # 4. Rebuild the source file, *excluding* lines within these extents
    $lines = $script:Source -split "`r?`n"
    $keep = New-Object System.Collections.Generic.List[string]
    $removedCount = 0

    for ($i = 0; $i -lt $lines.Length; $i++) {
        $lineNum = $i + 1; $inside = $false
        foreach ($u in $usedSpans) {
            if ($lineNum -ge $u.StartLine -and $lineNum -le $u.EndLine) {
                $inside = $true
                # Track that we are actively removing the first line of a block
                if ($lineNum -eq $u.StartLine) { $removedCount++ }
                break
            }
        }
        if (-not $inside) { $keep.Add($lines[$i]) }
    }

    # 5. Write the modified content back
    $newContent = $keep -join "`r`n"
    $newContent | Set-Content -Path $Psm1Path -Encoding UTF8

    Write-Host "Removed $removedCount function/class definition(s) from source. Original backed up at $bak"
    # 6. Reload the AST since the source has changed
    Load-AstAndSource -Path $Psm1Path
}
function Ensure-OutDirs {
    param([string]$BaseOut)
    $script:PublicDir = Join-Path $BaseOut 'Public'; $script:PrivateDir = Join-Path $BaseOut 'Private'; $script:ClassDir = Join-Path $BaseOut 'Class'
    @($script:PublicDir, $script:PrivateDir, $script:ClassDir) | ForEach-Object { New-Item -Path $_ -ItemType Directory -Force | Out-Null }
}
# ------------------------------------------
function List-Functions {
    if (-not $script:FunctionAsts) { Write-Host "No module loaded or no functions."; return }
    for ($i=0; $i -lt $script:FunctionAsts.Count; $i++) {
        $f = $script:FunctionAsts[$i]; $first = ($f.Extent.Text -split "`r?`n",2)[0].Trim()
        Write-Host ("[{0}] {1}" -f ($i+1), $first)
    }
}
function Select-Multi {
    param([Parameter(Mandatory=$true)][string[]]$Items, [string]$Prompt = "Select items (multi-select)")
    $psfzfFunc = Get-Command -Name Invoke-Fzf -ErrorAction SilentlyContinue
    if ($psfzfFunc) {
        try { return Invoke-Fzf -Items $Items -Multi -Prompt $Prompt } catch { Write-Warning "Invoke-Fzf failed. Falling back." }
    }
    if ($Host.Name -ne 'ServerRemoteHost' -and (Get-Command Out-GridView -ErrorAction SilentlyContinue)) {
        try { return $Items | Out-GridView -Title $Prompt -OutputMode Multiple } catch { Write-Warning "Out-GridView failed." }
    }
    Write-Host $Prompt
    for ($i = 0; $i -lt $Items.Count; $i++) { Write-Host ("[{0}] {1}" -f ($i+1), $Items[$i]) }
    $sel = Read-Host "Enter numbers separated by commas (e.g. 1,3,4) or 'a' for all"
    if ($sel -eq 'a') { return $Items }
    $indexes = $sel -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ - 1 } | Where-Object { $_ -ge 0 -and $_ -lt $Items.Count }
    $result = @(); foreach ($idx in $indexes) { $result += $Items[$idx] }; return $result
}
function Normalize-FunctionText { param([string]$rawText)
    $braceIndex = $rawText.IndexOf('{'); if ($braceIndex -lt 0) { return $rawText.Trim() }
    $header = $rawText.Substring(0, $braceIndex).Trim(); $body = $rawText.Substring($braceIndex)
    if ($header -match '(?i)\bfunction\b') { $header = ($header -replace '(?i)\bfunction\b','').Trim() }
    if ($header -match '^[a-zA-Z]+\s*:\s*(.+)$') { $name = $matches[1].Trim() } else { $name = $header.Trim() }
    $name = $name -replace '\s*\(.*$',''; return "function $name $body"
}
# ------------------------------------------
function Search-DirectoryForPsm1 {
    [CmdletBinding()]
    param(
        [Parameter(Position=0)][string]$Path = (Get-Location),
        [Parameter()][switch]$Recurse,
        [int]$MaxDepth = 6,
        [string[]]$SkipDirs = @('.git','node_modules','bin','obj'),
        [switch]$IncludeHidden = $false,
        [string]$Filter = '*.psm1',
        [switch]$Pick,
        [switch]$UseFzfIfAvailable
    )

    $start = (Resolve-Path -Path $Path -ErrorAction SilentlyContinue)
    if (-not $start) { Throw "Path not found: $Path" }
    $start = $start.Path

    $results = New-Object System.Collections.Generic.List[System.IO.FileInfo]
    $queue = New-Object System.Collections.Generic.Queue[System.Tuple[string,int]]
    $queue.Enqueue([System.Tuple]::Create($start, 0))

    while ($queue.Count -gt 0) {
        $pair = $queue.Dequeue()
        $dir = $pair.Item1
        $depth = $pair.Item2

        try {
            $files = Get-ChildItem -Path $dir -File -Force:($IncludeHidden.IsPresent) -Filter $Filter -ErrorAction Stop
            foreach ($f in $files) { $results.Add($f) }
        } catch { }

        if ($Recurse -and $depth -lt $MaxDepth) {
            try {
                $subdirs = Get-ChildItem -Path $dir -Directory -Force:($IncludeHidden.IsPresent) -ErrorAction Stop
                foreach ($sd in $subdirs) {
                    if ($SkipDirs -and ($SkipDirs -contains $sd.Name)) { continue }
                    $queue.Enqueue([System.Tuple]::Create($sd.FullName, $depth + 1))
                }
            } catch { }
        }
    }

    $arr = $results | Sort-Object -Property FullName

    if ($Pick) {
        $fzf = Get-Command -Name Invoke-Fzf -ErrorAction SilentlyContinue
        if ($UseFzfIfAvailable -and $fzf) {
            try {
                $items = $arr | ForEach-Object { $_.FullName }
                $pick = Invoke-Fzf -Items $items -Prompt 'Select a .psm1 file'
                if ($pick) { return (Get-Item -Path $pick) }
                return $null
            } catch { }
        }

        if ($Host.Name -ne 'ServerRemoteHost' -and (Get-Command Out-GridView -ErrorAction SilentlyContinue)) {
            try {
                $pick = $arr | Select-Object -ExpandProperty FullName | Out-GridView -Title 'Select a .psm1 file' -OutputMode Single
                if ($pick) { return (Get-Item -Path $pick) }
                return $null
            } catch { }
        }

        if (-not $arr -or $arr.Count -eq 0) {
            Write-Host "No .psm1 files found."
            return @()
        }
        for ($i = 0; $i -lt $arr.Count; $i++) {
            Write-Host ("[{0}] {1}" -f ($i+1), $arr[$i].FullName)
        }
        $sel = Read-Host "Enter number of file to pick (or empty to cancel)"
        if ($sel -and $sel -match '^\d+$' -and [int]$sel -ge 1 -and [int]$sel -le $arr.Count) {
            return $arr[[int]$sel - 1]
        }
        return $null
    }

    return ,$arr
}
#endregion
#==========================================#
#endregion
#==========================================#
#==========================================#
#region * Show-InteractiveMenu (Exported) *
#==========================================#
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
#endregion
#==========================================#
#==========================================#
#region * Menu configuration *
#==========================================#
$MenuOptions = @(
    [PSCustomObject]@{ Id = '1'; Shortcut = 'C'; Name = 'Load/Select PSM1 Module';          Help = 'Choose a .psm1 and prepare output dirs';                        Enabled = $true
        Type = 'PS'
        Action = {  $Psm1Path = Choose-Psm1File
                    if ($Psm1Path) {
                        Load-AstAndSource -Path $Psm1Path
                        Ensure-OutDirs -BaseOut $GlobalConfig.OutDir } } }
    [PSCustomObject]@{ Id = '2'; Shortcut = 'L'; Name = 'List Parsed Functions';            Help = 'Show parsed functions from loaded module';                      Enabled = $true
        Type = 'PS'
        Action = { List-Functions } }
    [PSCustomObject]@{ Id = '3'; Shortcut = 'I'; Name = 'Interactive Move Functions';       Help = 'Interactive multi-select move';                                 Enabled = $true
        Type = 'PS'
        Action = { Interactive-MoveFunctions } }
    [PSCustomObject]@{ Id = '4'; Shortcut = 'A'; Name = 'Export All Classes';               Help = 'Export classes into Class folder';                              Enabled = $true
        Type = 'PS'
        Action = { Export-AllClasses } }
    [PSCustomObject]@{ Id = '5'; Shortcut = 'X'; Name = 'Generate Module Index';            Help = 'Create index module that dot-sources public members';           Enabled = $true
        Type = 'PS'
        Action = { Generate-ModuleIndex } }
    [PSCustomObject]@{ Id = '6'; Shortcut = 'W'; Name = 'Write Helper/Misc Code';           Help = 'Write remaining private helpers';                               Enabled = $true
        Type = 'PS'
        Action = { Write-Helpers } }
    [PSCustomObject]@{ Id = '7'; Shortcut = 'R'; Name = 'Remove Moved from Source';         Help = 'Modify original .psm1 and create backup after confirmation';    Enabled = $true
        Type = 'PS'
        Action = {  if (-not $Psm1Path) {
                    Write-Warning 'No module loaded.'
                    return }
                    $c = Read-Host 'This modifies the source file and creates a backup. Proceed? (y/n) [n]'
                    if ($c -match '^(y|Y)') {
                        Remove-MovedFromSource
                    } else {
                        Write-Host 'Canceled.' } } }
    [PSCustomObject]@{ Id = '8'; Shortcut = 'M'; Name = 'Example: Run CMD Script';          Help = 'Metadata-only row demonstrating File/Type';                     Enabled = $true
        Type = 'CMD'
        File = 'mock-script.py'
        Action = $null }
    [PSCustomObject]@{ Id = 'Q'; Shortcut = 'Q'; Name = 'Quit Menu';                        Help = 'Exit menu';                                                     Enabled = $true
        Type = 'Meta'
        Action = { return 'quit' } }
)
#endregion
#==========================================#
# Initial load and OutDir setup
#==========================================#
$MyScriptDir = try { Split-Path -Parent $MyInvocation.MyCommand.Path -ErrorAction Stop } catch { (Get-Location).Path }

Show-InteractiveMenu `
    -MenuData $MenuOptions `
    -MenuSwitches $DefaultSwitches `
    -Title "PowerShell Module Splitter" `
    -ScriptDir $MyScriptDir `
    -EnablePersistence

#==========================================#


#==========================================#
#==========================================#
#==========================================#
#region * Old Parts *
#==========================================#
<#

$MenuActions = @(
    @{ Key = '1'; Name = 'Select .psm1 file';                                                   Action = {
        $p = Choose-Psm1File -AllowFilesystemSearch
        if ($p) {
            $script:Psm1Path = $p
            Load-AstAndSource -Path $script:Psm1Path
            $base = (Split-Path -Leaf $script:Psm1Path) -replace '\.psm1$',''
            if (-not $script:OutDir) {
                $script:OutDir = Join-Path -Path (Split-Path -Parent $script:Psm1Path) -ChildPath ($base + '-Split')
            }
            Ensure-OutDirs -BaseOut $script:OutDir
            Write-Host "Loaded $script:Psm1Path" } } }
    @{ Key = '2'; Name = 'List functions in loaded module';                                     Action = { List-Functions } }
    @{ Key = '3'; Name = 'Interactive move functions (multi-select)';                           Action = {
        if (-not $script:Psm1Path) { Write-Warning "No module loaded. Choose one first."; return }
        Interactive-MoveFunctions } }
    @{ Key = '4'; Name = 'Export all classes to Class folder';                                  Action = {
        if (-not $script:Psm1Path) { Write-Warning "No module loaded."; return }
        Export-AllClasses } }
    @{ Key = '5'; Name = 'Generate index module that dot-sources Public members';               Action = {
        if (-not $script:OutDir) { Write-Warning "No OutDir configured."; return }
        Generate-Index } }
    @{ Key = '6'; Name = 'Write Private helpers file (remaining non-function/class content)';   Action = {
        if (-not $script:Psm1Path) { Write-Warning "No module loaded."; return }
        Write-Helpers } }
    @{ Key = '7'; Name = 'Remove moved functions from original .psm1 (creates backup)';         Action = {
        if (-not $script:Psm1Path) { Write-Warning "No module loaded."; return }
        $c = Read-Host "This modifies the source file and creates a backup. Proceed? (y/n) [n]"
        if ($c -match '^(y|Y)') { Remove-MovedFromSource } else { Write-Host "Canceled." } } }
    @{ Key = 'q'; Name = 'Quit';                                                                Action = { return 'quit' } }
)

$MenuOptions = @(
    [PSCustomObject]@{ Key = 'C' ; Name = 'Choose PSM1 File';      Action = { Choose-Psm1File } }
    [PSCustomObject]@{ Key = 'S' ; Name = 'Search Module Paths';   Action = { Search-DirectoryForPsm1 | Out-Null } } # Added New Option
    [PSCustomObject]@{ Key = 'I' ; Name = 'Interactive Move';      Action = { Interactive-Move } }
    [PSCustomObject]@{ Key = 'E' ; Name = 'Export Classes';        Action = { Export-Classes } }
    [PSCustomObject]@{ Key = 'X' ; Name = 'Generate Index';        Action = { Generate-ModuleIndex } }
    [PSCustomObject]@{ Key = 'W' ; Name = 'Write Helpers';         Action = { Write-Helpers } }
    [PSCustomObject]@{ Key = 'R' ; Name = 'Remove Moved Functions';Action = { Remove-MovedFunctions } }
    [PSCustomObject]@{ Key = 'Q' ; Name = 'Quit';                  Action = { exit } }
)

function Get-SafeConsoleColor {
    param(
        [Parameter(Mandatory=$true)][object]$ColorValue,
        [string]$Default = 'Gray'
    )
    if ($null -eq $ColorValue -or $ColorValue -eq '') { return $Default }
    try {
        # Accept both ConsoleColor names and numeric enum values
        if ($ColorValue -is [System.ConsoleColor]) { return $ColorValue.ToString() }
        $s = [string]$ColorValue
        # If it's numeric, try to cast
        if ($s -match '^\d+$') {
            $num = [int]$s
            return ([System.ConsoleColor]$num).ToString()
        }
        # Try parse by name (case-insensitive)
        return ([Enum]::Parse([System.ConsoleColor], $s, $true)).ToString()
    } catch {
        return $Default
    }
}
function Write-HostWithColor {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        [ConsoleColor]$ForegroundColor = 'White',
        [ConsoleColor]$BackgroundColor = 'Black'
    )
    Write-Host $Message -ForegroundColor $ForegroundColor -BackgroundColor $BackgroundColor
}
function Show-CenteredText {
    < #
        .SYNOPSIS
            Display a centered block of text with optional box, padding, and token.
        .PARAMETER Text
            Text to display. Accepts pipeline input and multi-line strings.
        .PARAMETER Width
            Maximum width for the text block (including padding and token). Defaults to console width.
        .PARAMETER Wrap
            If true, long lines will be wrapped to fit the width.
        .PARAMETER Padding
            Spaces added inside the block on left and right of text.
        .PARAMETER Margin
            Blank lines printed above and below the block.
        .PARAMETER Token
            Optional token shown at the start of each line (e.g., arrow or label).
        .PARAMETER TokenColored
            If true, token uses TokenFg/TokenBg.
        .PARAMETER TextColored
            If true, main text is rendered with TextFg/TextBg.
        .PARAMETER Box
            If true, draws a single-line box around the text block using Unicode box characters.
    # >
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string] $Text,
        [int] $Width = 0,
        [bool] $Wrap = $true,
        [int] $Padding = 1,
        [int] $Margin = 0,
        [string] $Token = '',
        [bool] $TokenColored = $false,
        [ConsoleColor] $TokenFg = 'Yellow',
        [ConsoleColor] $TokenBg = 'DarkBlue',
        [ConsoleColor] $TextFg = 'White',
        [ConsoleColor] $TextBg = 'DarkBlue',
        [bool] $TextColored = $false,
        [bool] $Box = $false
    )
    begin {
        try { $consoleWidth = [Math]::Max(10, [Console]::WindowWidth) } catch { $consoleWidth = 80 }
        if ($Width -le 0 -or $Width -gt $consoleWidth) { $Width = $consoleWidth }
        $innerMax = $Width - 2 * $Padding
        if ($Token) { $innerMax -= ($Token.Length + 1) } # token + space
        if ($innerMax -lt 1) { $innerMax = 1 }
    }
    process {
        if ($null -eq $Text) { return }
        $rawLines = $Text -split "`r?`n"
        $lines = [System.Collections.Generic.List[string]]::new()
        foreach ($ln in $rawLines) {
            if ($Wrap -and $ln.Length -gt $innerMax) {
                $start = 0
                while ($start -lt $ln.Length) {
                    $len = [Math]::Min($innerMax, $ln.Length - $start)
                    $lines.Add($ln.Substring($start, $len))
                    $start += $len
                }
            } else { $lines.Add($ln) }
        }
        for ($i = 0; $i -lt $Margin; $i++) { [Console]::WriteLine() }
        if ($Box) {
            $top = "┌" + ("─" * ($Width - 2)) + "┐"
            Write-Plain $top
            [Console]::WriteLine()
        }
        foreach ($line in $lines) {
            $trimmed = $line
            if ($trimmed.Length -gt $innerMax) { $trimmed = $trimmed.Substring(0, $innerMax) }
            $contentPad = $innerMax - $trimmed.Length
            $leftPadInside = [int][Math]::Floor($contentPad / 2)
            $rightPadInside = $contentPad - $leftPadInside
            $row = (' ' * $Padding)
            if ($Token) {
                $row += $Token
                if ($trimmed) { $row += ' ' }
            }
            $row += (' ' * $leftPadInside) + $trimmed + (' ' * $rightPadInside) + (' ' * $Padding)
            if ($Box) { $row = "│" + $row + "│" }
            $padLeft = [Math]::Max(0, [int][Math]::Floor(($consoleWidth - $row.Length) / 2))
            $padRight = $consoleWidth - $padLeft - $row.Length
            Write-Plain (' ' * $padLeft)
            if ($Token) {
                if ($TokenColored) { Write-Colored -Text $Token -Fg $TokenFg -Bg $TokenBg
                    if ($trimmed) { Write-Plain ' ' }
                } else { Write-Plain $Token
                    if ($trimmed) { Write-Plain ' ' }
                }
            }
            $textArea = (' ' * $Padding) + (' ' * $leftPadInside) + $trimmed + (' ' * $rightPadInside) + (' ' * $Padding)
            if ($Box) { Write-Plain '│' }
            if ($TextColored) { Write-Colored -Text $textArea -Fg $TextFg -Bg $TextBg }
            else { Write-Plain $textArea }
            if ($Box) { Write-Plain '│' }
            Write-Plain (' ' * $padRight)
            [Console]::WriteLine()
        }
        if ($Box) {
            $bottom = "└" + ("─" * ($Width - 2)) + "┘"
            Write-Plain $bottom
            [Console]::WriteLine()
        }
        for ($i = 0; $i -lt $Margin; $i++) { [Console]::WriteLine() }
    }
}

#>
#endregion
#==========================================#
