#==========================================#
#region * Switches and Configuration *
#==========================================#
$DefaultSwitches = @(
    [PSCustomObject]@{ Id = 'N' ; Name = 'Navigation Mode';    State = $navMode;   Type = 'Choice'; Description = 'Toggle Arrow Key or Numeric selection'
        Text    = "Nav: $navMode"
        Value   = $navMode
        TextFg  = $GlobalConfig.InfoColor
        TextBg  = $GlobalConfig.BackgroundColor
        Fg      = if ($navMode -eq 'Arrow') { $GlobalConfig.SelectedTextColor } else { $GlobalConfig.InfoColor }
        Bg      = if ($navMode -eq 'Arrow') { $GlobalConfig.SelectedTextBg } else { $GlobalConfig.BackgroundColor } }
    [PSCustomObject]@{ Id = 'E' ; Name = 'Show Exec Path';     State = $showExec;  Type = 'Toggle'; Description = 'Show/Hide the script execution path'
        Text    = "Path: $showExec"
        Value   = [bool]$showExec
        TextFg  = $GlobalConfig.InfoColor
        TextBg  = $GlobalConfig.BackgroundColor
        Fg      = if ($showExec) { $GlobalConfig.ToggleOnFg } else { $GlobalConfig.MutedColor }
        Bg      = if ($showExec) { $GlobalConfig.ToggleOnBg } else { $GlobalConfig.BackgroundColor } },
    [PSCustomObject]@{ Id = 'D' ; Name = 'Debug Mode';         State = $debug;     Type = 'Toggle'; Description = 'Verbose logging for scripts'
        Text    = "DEBUG: $debugText"
        Value   = [bool]$debug
        TextFg  = $GlobalConfig.InfoColor
        TextBg  = $GlobalConfig.BackgroundColor
        Fg      = if ($debug) { $GlobalConfig.ToggleOnFg } else { $GlobalConfig.MutedColor }
        Bg      = if ($debug) { $GlobalConfig.ToggleOnBg } else { $GlobalConfig.BackgroundColor } },
    [PSCustomObject]@{ Id = 'R' ; Name = 'Dry-Run Mode';       State = $dryRun;    Type = 'Toggle'; Description = 'Prevent actual script execution'
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
$ActionRegistry = @{}
function Register-Action {
    param([string]$Id, [ScriptBlock]$Script)
    if (-not $Id) { throw 'Id required' }
    $ActionRegistry[$Id] = $Script
}

$DefaultRehydrateMap = @{
    'Psm1Path'   = { if (Get-Variable -Name 'Psm1Path' -Scope Script -ErrorAction SilentlyContinue) { (Get-Variable -Name 'Psm1Path' -Scope Script).Value } elseif (Get-Variable -Name 'Psm1Path' -Scope Global -ErrorAction SilentlyContinue) { (Get-Variable -Name 'Psm1Path' -Scope Global).Value } else { $null } }
    'OutDir'     = { if (Get-Variable -Name 'GlobalConfig' -Scope Script -ErrorAction SilentlyContinue) { $g=(Get-Variable -Name 'GlobalConfig' -Scope Script).Value; if ($g -and $g.OutDir) { $g.OutDir } else { $null } } elseif (Get-Variable -Name 'GlobalConfig' -Scope Global -ErrorAction SilentlyContinue) { $g=(Get-Variable -Name 'GlobalConfig' -Scope Global).Value; if ($g -and $g.OutDir) { $g.OutDir } else { $null } } else { $null } }
    'LastUsed'   = { (Get-Date) }
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
#endregion
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
#endregion
#==========================================#
#region ----- PUBLIC Functions -----
#==========================================#
function New-InteractiveMenuTheme {
    <#
        .SYNOPSIS
            Creates a new MenuTheme object for customizing interactive menus.
        .DESCRIPTION
            This function creates an instance of the MenuTheme class, allowing you
            to define custom colors for use with Invoke-InteractiveMenu.
        .PARAMETER AccentColor
            The color for the title and non-selected menu items.
        .PARAMETER HighlightFg
            The foreground (text) color for the selected menu item.
        .PARAMETER HighlightBg
            The background color for the selected menu item.
        .PARAMETER PointerGlyph
            The string to use as the pointer (e.g., '➤ ' or '-> ').
        .PARAMETER HeaderTitleColor
            The color for the main header title.
        .PARAMETER StatusBarColor
            The color for the status bar text.
        .PARAMETER StatusBarBgColor
            The color for the status bar background.
        .EXAMPLE
            $myTheme = New-InteractiveMenuTheme -AccentColor Green -HighlightFg Black -HighlightBg Green
            Invoke-InteractiveMenu -Title "My Menu" -ActionArray $actions -Theme $myTheme
    #>
    [CmdletBinding()]
    [OutputType([MenuTheme])]
    param(
        [ConsoleColor]$AccentColor          = 'Cyan',
        [ConsoleColor]$HighlightFg          = 'Black',
        [ConsoleColor]$HighlightBg          = 'White',
        [string]$PointerGlyph               = '➤ ',
        [ConsoleColor]$HeaderTitleColor     = 'Cyan',
        [ConsoleColor]$StatusBarColor       = 'Yellow',
        [ConsoleColor]$StatusBarBgColor     = 'DarkBlue'
    )
    $theme = [MenuTheme]::new()
    $theme.AccentColor = $AccentColor
    $theme.HighlightFg = $HighlightFg
    $theme.HighlightBg = $HighlightBg
    $theme.PointerGlyph = $PointerGlyph
    $theme.HeaderTitleColor = $HeaderTitleColor
    $theme.StatusBarColor = $StatusBarColor
    $theme.StatusBarBgColor = $StatusBarBgColor
    return $theme
}

function Get-InteractiveMenuSwitch {
    <#
    .SYNOPSIS
        Gets the current state of a menu switch.
    .PARAMETER Id
        The ID of the switch to get (e.g., 'D' for Debug, 'R' for Dry-Run).
    .EXAMPLE
        Get-InteractiveMenuSwitch -Id 'D'
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$Id
    )
    return private:Get-SwitchById -Id $Id
}

function Set-InteractiveMenuSwitch {
    <#
    .SYNOPSIS
        Sets the state of a menu switch.
    .DESCRIPTION
        Toggles a 'Toggle' switch or sets the value of a 'Choice' switch.
    .PARAMETER Id
        The ID of the switch to set (e.g., 'D', 'R').
    .PARAMETER State
        (Optional) The specific state to set. If omitted for a 'Toggle'
        switch, the switch's state will be inverted.
    .EXAMPLE
        Set-InteractiveMenuSwitch -Id 'D' # Toggles Debug mode
    .EXAMPLE
        Set-InteractiveMenuSwitch -Id 'D' -State $true # Sets Debug mode to On
    .EXAMPLE
        Set-InteractiveMenuSwitch -Id 'N' -State 'Numeric' # Sets Navigation mode
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Id,
        [object]$State
    )
    if ($PSBoundParameters.ContainsKey('State')) {
        return private:Set-SwitchState -Id $Id -State $State
    } else {
        return private:Set-SwitchState -Id $Id
    }
}

function Save-InteractiveMenuSwitches {
    <#
    .SYNOPSIS
        Saves the current switch states to a JSON file.
    .PARAMETER Path
        (Optional) The path to save the file to.
        Defaults to "$env:APPDATA\InteractiveMenu\switches.json".
    .EXAMPLE
        Save-InteractiveMenuSwitches
    #>
    [CmdletBinding()]
    param(
        [string]$Path = $script:SwitchSavePath
    )
    return private:Save-SwitchStates -Path $Path
}

function Load-InteractiveMenuSwitches {
    <#
    .SYNOPSIS
        Loads switch states from a JSON file.
    .PARAMETER Path
        (Optional) The path to load the file from.
        Defaults to "$env:APPDATA\InteractiveMenu\switches.json".
    .EXAMPLE
        Load-InteractiveMenuSwitches
    #>
    [CmdletBinding()]
    param(
        [string]$Path = $script:SwitchSavePath
    )
    return private:Load-SwitchStates -Path $Path
}

function Reset-InteractiveMenuSwitches {
    <#
        .SYNOPSIS
            Resets all switches to their default values.
        .EXAMPLE
            Reset-InteractiveMenuSwitches
    #>
    [CmdletBinding()]
    param()
    $script:ActiveMenuSwitches = $script:DefaultMenuSwitches.Clone()
    return $script:ActiveMenuSwitches
}
#endregion
#==========================================#
#region * Menu Functions *
#==========================================#
function Invoke-InteractiveMenu {
    <#
    .SYNOPSIS
        Displays a powerful, themed, arrow-key navigable menu.
    .DESCRIPTION
        This function displays an interactive menu based on an array of action
        objects. It handles all navigation, rendering, and action execution.
        It supports sub-menus by allowing an action to call Invoke-InteractiveMenu again.
    .PARAMETER Title
        The title string to display at the top of the menu.
    .PARAMETER ActionArray
        An array of hashtables or [ActionObject]s. Each object must have:
        - Label (string): The text to display for the menu item.
        - Action (scriptblock): The code to execute when the item is selected.
    .PARAMETER Subtitle
        An optional array of strings to display below the title.
    .PARAMETER Theme
        An optional [MenuTheme] object (created by New-InteractiveMenuTheme)
        to customize the menu's appearance.
    .EXAMPLE
      $MenuItems = @(
          [PSCustomObject]@{ Id    = '1'; Name = '5 Minute Shutdown'; Enabled = $true
                            Key    = 's'
                            Help   = 'Initiates a 5-minute system shutdown.'
                            Type   = 'Action'
                            Action = { Shutdown-5Min } }
          [PSCustomObject]@{  Id     = '0'; Name = 'Exit'; Enabled = $true
                              Key    = 'x'
                              Help   = 'Exits the script.'
                              Type   = 'Exit'
                              Action = { Write-Host "Exiting script." } }
      )
      Invoke-InteractiveMenu -Title "Main Menu" -ActionArray $actions
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][object[]]$ActionArray,
        [string[]]$Subtitle,
        [MenuTheme]$Theme = $private:DefaultMenuTheme
    )

    if (-not $Theme -or -not ($Theme -is [MenuTheme])) { $Theme = $private:DefaultMenuTheme }

    $menuItems = @()
    if ($ActionArray) {
        foreach ($item in $ActionArray) {
            $menuItems += [string]$item.Label
        }
    }

    if (-not $menuItems -or $menuItems.Count -eq 0) {
        private:Write-MenuColor -Level Error -Message "No menu actions provided."
        return $private:EXIT_CODE
    }

    $null = Register-EngineEvent PowerShell.Exiting -Action { private:Show-Cursor } -SupportEvent

    do {
        $selection = private:Show-InteractiveMenu -Title $Title `
                                          -Options $menuItems `
                                          -Theme $Theme `
                                          -Subtitle $Subtitle

        if ($selection -eq $private:EXIT_CODE) { return $private:EXIT_CODE }
        if ($selection -eq $private:BACK_CODE) { return $private:BACK_CODE }

        if ($selection -ge 0 -and $selection -lt ($ActionArray.Count)) {
            $selectedLabel = ($ActionArray[$selection]).Label
            $result = $null
            try {
                $result = & $ActionArray[$selection].Action
            } catch {
                private:Write-MenuColor -Level Error -Message "Action threw an exception: $_"
                Read-Host "Press Enter to continue..." | Out-Null
            }

            if ($result -eq $private:EXIT_CODE) { return $private:EXIT_CODE }
        }
    } while ($true)
}

function Invoke-DashboardMenu {
    <#
        .SYNOPSIS
            Displays an interactive menu with a live, auto-refreshing status panel.
        .DESCRIPTION
            This function creates a split-pane menu. The top pane is an arrow-key
            navigable menu, and the bottom pane is a "status panel" that refreshes
            on a timer by executing a provided scriptblock.
        .PARAMETER MenuItems
            An array of hashtables defining the menu items. Each must have:
            - Key (string): The hotkey (e.g., '1', 'S', 'Q').
            - Label (string): The text to display for the menu item.
        .PARAMETER Title
            The title string for the top of the menu.
        .PARAMETER Summary
            A (non-refreshing) summary line to display below the title.
        .PARAMETER StatusScriptBlock
            A [ScriptBlock] that will be executed on a timer. This scriptblock
            MUST return an array of objects, where each object has a 'Name'
            and 'Value' property (e.g., @{ Name = 'Service Status'; Value = 'Running' }).
        .PARAMETER InitialIndex
            The 0-based index of the menu item to select by default.
        .PARAMETER StatusRefreshSeconds
            The number of seconds between status panel refreshes.
        .EXAMPLE
      $MenuItems = @(
          [PSCustomObject]@{ Id    = '1'; Name = '5 Minute Shutdown'; Enabled = $true
                            Key    = 's'
                            Help   = 'Initiates a 5-minute system shutdown.'
                            Type   = 'Action'
                            Action = { Shutdown-5Min } }
          [PSCustomObject]@{  Id     = '0'; Name = 'Exit'; Enabled = $true
                              Key    = 'x'
                              Help   = 'Exits the script.'
                              Type   = 'Exit'
                              Action = { Write-Host "Exiting script." } }
      )
            $choice = Invoke-DashboardMenu -MenuItems $menu -Title "Service" -StatusScriptBlock $statusBlock
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [array]$MenuItems,
        [Parameter(Mandatory)]
        [ScriptBlock]$StatusScriptBlock,
        [string]$Title,
        [string]$Summary,
        [int]$InitialIndex          = 0,
        [int]$StatusRefreshSeconds  = 2
    )

    # --- Nested Helper Functions ---
    function private:nested:Get-Cursor {
        try { return $Host.UI.RawUI.CursorPosition } catch { return @{X=0; Y=0} }
    }
    function private:nested:Set-Cursor($pos) {
        try { $Host.UI.RawUI.CursorPosition = $pos } catch {}
    }
    function private:nested:Write-CenteredLine {
        param($text, $fg = 'White', $bg = $null)
        try { $w = $Host.UI.RawUI.WindowSize.Width } catch { $w = [Console]::WindowWidth }
        $text = [string]$text
        $pad = [Math]::Max(0, [Math]::Floor(($w - $text.Length) / 2))
        $prefix = ' ' * $pad
        if ($bg) {
            Write-Host ($prefix + $text) -ForegroundColor $fg -BackgroundColor $bg
        } else {
            Write-Host ($prefix + $text) -ForegroundColor $fg
        }
    }
    # --- End Nested Helpers ---

    if (-not $MenuItems -or $MenuItems.Count -eq 0) {
        throw "MenuItems must be a non-empty array of objects with properties 'Key' and 'Label'."
    }
    if ($InitialIndex -lt 0 -or $InitialIndex -ge $MenuItems.Count) {
        $InitialIndex = 0
    }

    $currentIndex = [int]$InitialIndex
    $cachedStatus = $null
    $lastStatusUpdate = [datetime]::UtcNow.AddSeconds(-9999)
    $statusPanelTop = 0
    $menuHeight = 0

    # --- Nested Layout and Drawing Functions ---

    function private:nested:Update-Layout {
        try {
            $width  = $Host.UI.RawUI.WindowSize.Width
            $height = $Host.UI.RawUI.WindowSize.Height
        } catch {
            $width  = [Console]::WindowWidth
            $height = [Console]::WindowHeight
        }

        $titleLines = if ($Title)   { 1 } else { 0 }
        $summaryLines = if ($Summary) { 1 } else { 0 }
        $menuItemsLines = $MenuItems.Count
        $menuHeight = $titleLines + $summaryLines + 1 + $menuItemsLines  # +1 blank line after summary

        $statusPanelTop = [Math]::Min([Math]::Max($menuHeight + 1, [Math]::Floor($height / 1.8)), $height - 4)
        if ($statusPanelTop -lt $menuHeight + 1) { $statusPanelTop = $menuHeight + 1 }
        if ($statusPanelTop -gt ($height - 4)) { $statusPanelTop = $height - 4 }
    }

    function private:nested:Draw-Menu {
        private:nested:Update-Layout
        $cursorPos = private:nested:Get-Cursor
        try { private:nested:Set-Cursor @{X=0; Y=0} } catch {}

        try {
            $w = $Host.UI.RawUI.WindowSize.Width
            for ($y = 0; $y -lt $statusPanelTop; $y++) {
                private:nested:Set-Cursor @{X=0; Y=$y}
                Write-Host (' ' * $w) -NoNewline
            }
        } catch {
            Clear-Host
        }

        private:nested:Set-Cursor @{X=0; Y=0}

        # --- MODIFIED: Integrate Switch Status ---
        try { $debug = [bool](private:Get-SwitchById -Id 'D').State } catch { $debug = $false }
        try { $dryRun = [bool](private:Get-SwitchById -Id 'R').State } catch { $dryRun = $false }
        $debugText = if ($debug) { '[DEBUG]' } else { '' }
        $dryRunText = if ($dryRun) { '[DRY-RUN]' } else { '' }
        $switchText = ($debugText, $dryRunText | Where-Object { $_ }).Trim() -join ' '
        $finalTitle = $Title
        if ($switchText) {
            $finalTitle = "$finalTitle $switchText"
        }
        # --- End Modification ---

        if ($Title) {
            private:nested:Write-CenteredLine ("==== $finalTitle ====") 'Cyan'
        }
        if ($Summary) {
            private:nested:Write-CenteredLine $Summary 'Gray'
            Write-Host ""
        } else {
            Write-Host ""
        }

        for ($i = 0; $i -lt $MenuItems.Count; $i++) {
            $item = $MenuItems[$i]
            $line = "  [$($item.Key)] $($item.Label)"
            if ($i -eq $currentIndex) {
                Write-Host $line -ForegroundColor Black -BackgroundColor Yellow
            } else {
                Write-Host $line -ForegroundColor White
            }
        }

        try { private:nested:Set-Cursor @{X=0; Y=($menuHeight + 1)} } catch {}
        private:nested:Set-Cursor $cursorPos
    }

    function private:nested:Draw-StatusPanel {
        private:nested:Update-Layout
        $cursorPos = private:nested:Get-Cursor
        try { private:nested:Set-Cursor @{X=0; Y=$statusPanelTop} } catch {}

        try {
            $w = $Host.UI.RawUI.WindowSize.Width
        } catch {
            $w = [Console]::WindowWidth
        }

        Write-Host ('=' * $w) -ForegroundColor DarkGray
        private:nested:Write-CenteredLine "Live Status (Refreshes every $StatusRefreshSeconds s)" 'Yellow'
        Write-Host ""

        if (-not $cachedStatus) {
            Write-Host "Updating status..." -ForegroundColor DarkGray
        } else {
            $nameWidth = 0
            foreach ($r in $cachedStatus) {
                if ($r.Name) {
                    $nlen = ($r.Name).ToString().Length
                    if ($nlen -gt $nameWidth) { $nameWidth = $nlen }
                }
            }
            $nameWidth = [Math]::Min($nameWidth, [Math]::Floor($w * 0.4))
            $valWidth = $w - $nameWidth - 5

            foreach ($r in $cachedStatus) {
                $name = $r.Name.ToString()
                $value = $r.Value.ToString()
                if ($name.Length -gt $nameWidth) { $name = $name.Substring(0, $nameWidth - 1) + '…' }
                if ($value.Length -gt $valWidth) { $value = $value.Substring(0, $valWidth - 1) + '…' }
                $line = ('{0} : {1}' -f $name.PadRight($nameWidth), $value)
                Write-Host $line -ForegroundColor Gray
            }
        }
        # Pad the rest of the status area
        $currentY = (private:nested:Get-Cursor).Y
        $bottomY = $Host.UI.RawUI.WindowSize.Height - 2
        while ($currentY -lt $bottomY) {
            Write-Host (' ' * $w) -NoNewline
            $currentY++
        }
        private:nested:Set-Cursor @{X=0; Y=$bottomY}
        Write-Host ('=' * $w) -ForegroundColor DarkGray
        private:nested:Set-Cursor $cursorPos
    }

    # --- End Nested Drawing Functions ---

    private:nested:Update-Layout

    Add-Type -AssemblyName System.Timers | Out-Null
    $timer = New-Object System.Timers.Timer
    $timer.Interval = [Math]::Max(500, $StatusRefreshSeconds * 1000)
    $timer.AutoReset = $true
    $timer.SynchronizingObject = $null

    # Timer callback
    $timer.Add_Elapsed({
        try {
            $s = & $StatusScriptBlock
            $rows = @()
            if ($s -is [System.Collections.IEnumerable] -and -not ($s -is [string])) {
                foreach ($r in $s) {
                    if ($r.PSObject.Properties.Name -contains 'Name' -and $r.PSObject.Properties.Name -contains 'Value') {
                        $rows += @{ Name = $r.Name; Value = $r.Value }
                    } else {
                        $rows += @{ Name = 'Info'; Value = $r.ToString() }
                    }
                }
            } else {
                $rows += @{ Name = 'Info'; Value = $s.ToString() }
            }
            $cachedStatus = $rows
            $lastStatusUpdate = [datetime]::UtcNow
        } catch {
            $cachedStatus = @(@{ Name = 'Error'; Value = $_.Exception.Message })
            $lastStatusUpdate = [datetime]::UtcNow
        }
        private:nested:Draw-StatusPanel
    })

    $timer.Start()
    & $timer.Elapsed

    Clear-Host
    private:nested:Draw-Menu
    private:nested:Draw-StatusPanel

    try {
        $prevWindowSize = $Host.UI.RawUI.WindowSize
    } catch {
        $prevWindowSize = @{Width = [Console]::WindowWidth; Height = [Console]::WindowHeight}
    }

    try {
        while ($true) {
            try { $curSize = $Host.UI.RawUI.WindowSize } catch { $curSize = @{Width = [Console]::WindowWidth; Height = [Console]::WindowHeight} }

            if ($curSize.Width -ne $prevWindowSize.Width -or $curSize.Height -ne $prevWindowSize.Height) {
                $prevWindowSize = $curSize
                private:nested:Update-Layout
                Clear-Host
                private:nested:Draw-Menu
                private:nested:Draw-StatusPanel
            }

            if ($Host.UI.RawUI.KeyAvailable) {
                $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
                switch ($key.VirtualKeyCode) {
                    38 { # Up
                        $currentIndex = ($currentIndex - 1)
                        if ($currentIndex -lt 0) { $currentIndex = $MenuItems.Count - 1 }
                        private:nested:Draw-Menu
                    }
                    40 { # Down
                        $currentIndex = ($currentIndex + 1) % $MenuItems.Count
                        private:nested:Draw-Menu
                    }
                    13 { # Enter
                        $timer.Stop()
                        Clear-Host
                        return [string]$MenuItems[$currentIndex].Key
                    }
                    27 { # Escape
                        $timer.Stop()
                        Clear-Host
                        return 'Q'
                    }
                    Default {
                        $ch = $key.Character
                        if ($ch) {
                            $matched = $MenuItems | Where-Object { $_.Key -eq $ch -or $_.Key -eq $ch.ToUpper() } | Select-Object -First 1
                            if ($matched) {
                                $timer.Stop()
                                Clear-Host
                                return [string]$matched.Key
                            }
                        }
                    }
                }
            }

            Start-Sleep -Milliseconds 50
        }
    } finally {
        try { $timer.Stop(); $timer.Dispose() } catch {}
        private:Show-Cursor
    }
}
#endregion
#==========================================#
#region * Start Menu Loop *
#==========================================#

#endregion
#==========================================#
# --- Main Application Logic ---
# if script is run directly then
#if ($MyInvocation.MyCommand.Path) {
#    Start-MenuLoop -Actions $modulesMenuActions
#}

# SIG # Begin signature block
# MIIFvwYJKoZIhvcNAQcCoIIFsDCCBawCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCD3Vl4GxfwPf9NT
# aPePP21u/LcxNBfwxYPvxw6nsDBGtqCCAyYwggMiMIICCqADAgECAhBTL0G9/1qW
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
# LwYJKoZIhvcNAQkEMSIEIJygmLTHBbZ8CteSAPdZxdrNvHbuzWR3tWGoMqLlJWn0
# MA0GCSqGSIb3DQEBAQUABIIBAKdZN7d2NVoIodKgPfSNNSXFj6YqO0p6cHHvJqK1
# /1iYc/VIIXBn8eLpTqrW8p1gXIVIKo69gURWjZKa1mFvnTvDWWiCnOxup5gsGJ9s
# d9symK8Ol5WUUFyCfbGzrRN2KK11/qjGWtCsjfCizeDosyavzunGIHeYWxgQMArj
# Ka509UessqAWSU2qfgkcS8JjGljKTba2Uk99Ne1mY6XJENWzPJmD3vJs8E/QpUVi
# eWf/nsVsm2Nm9YU79kRIX9skDivhyHas039hXac69y20VDrNLnVmJnLGkDgpNEG9
# 3vHGBNUygb3BqSRWksxskqsLVwxg7UCnn8OLNDJY+iyIF9k=
# SIG # End signature block
