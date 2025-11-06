<#
    .SYNOPSIS
        A universal, enhanced PowerShell module for creating sophisticated,
        interactive console menus.
    .DESCRIPTION
        This module provides two main functions for menu creation:
        1. Invoke-InteractiveMenu:
        A powerful, theme-able, arrow-key navigable menu system.
        It supports sub-menus and is built on a class-based theme object.
        (Derived from PowershellProfileMenu.ps1)
        2. Invoke-DashboardMenu:
        A live, interactive dashboard menu with an auto-refreshing status panel.
        Ideal for scripts that need to display changing data alongside a menu.
        (Derived from SSH-Manager-Menu.ps1)
        It also exports helper functions for managing themes and persistent
        menu switches (like Debug or Dry-Run mode).
    .EXAMPLE
        Show-ExampleMenu
    .EXAMPLE
        $menu = @( @{ Key = '1'; Label = 'Start' }, @{ Key = 'Q'; Label = 'Quit' } )
#>
#==========================================#
#region * Constants, Classes, and State *
#==========================================#
[int]$private:EXIT_CODE = -99
[int]$private:BACK_CODE = -98

$script:DefaultMenuSwitches = @(
    [PSCustomObject]@{ Id = 'D' ; Name = 'Debug Mode';      State = $false;  Type = 'Toggle'; Description = 'Verbose logging for scripts' }
    [PSCustomObject]@{ Id = 'N' ; Name = 'Navigation Mode'; State = 'Arrow'; Type = 'Choice'; Description = 'Toggle Arrow Key or Numeric selection' }
    [PSCustomObject]@{ Id = 'R' ; Name = 'Dry-Run Mode';    State = $false;  Type = 'Toggle'; Description = 'Prevent actual script execution' }
)
# Active state for the switches
$script:ActiveMenuSwitches = $script:DefaultMenuSwitches.Clone()
# Persistence path for switches
$script:SwitchSavePath = Join-Path $env:APPDATA 'InteractiveMenu\switches.json'
# Class definition for menu themes
class MenuTheme {
    [ConsoleColor]$PromptInputColor        = 'White'
    [ConsoleColor]$PromptSuccessColor      = 'Green'
    [ConsoleColor]$PromptWarningColor      = 'Yellow'
    [ConsoleColor]$PromptActionColor       = 'Magenta'
    [ConsoleColor]$PromptInfoColor         = 'Cyan'
    [ConsoleColor]$PromptErrorColor        = 'Red'
    [ConsoleColor]$PromptMutedColor        = 'DarkGray'
    [ConsoleColor]$HeaderTitleColor       = 'Cyan'
    [ConsoleColor]$HeaderSubtitleColor    = 'DarkGray'
    [ConsoleColor]$HeaderUnderlineColor   = 'Blue'
    [ConsoleColor]$HeaderSpacelineColor   = 'Green'
    [ConsoleColor]$AccentColor            = 'Cyan'
    [ConsoleColor]$HighlightFg            = 'Black'
    [ConsoleColor]$HighlightBg            = 'White'
    [string]$PointerGlyph                 = '➤ '
    [ConsoleColor]$StatusBarColor         = 'Yellow'
    [ConsoleColor]$StatusBarBgColor       = 'DarkBlue'
}
# Class for menu actions
class ActionObject {
    [int]$Number
    [string]$Label
    [scriptblock]$Action
}
# Default theme instance
$private:DefaultMenuTheme = [MenuTheme]::new()
#endregion
#==========================================#
#region * Private: Switch Handlers *
#==========================================#
function private:Get-SwitchById {
    param(
        [string]$Id
    )
    # Operates on the script-scoped variable
    $script:ActiveMenuSwitches | Where-Object { $_.Id -eq $Id }
}

function private:Set-SwitchState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter()][object]$State
    )
    $s = private:Get-SwitchById -Id $Id
    if (-not $s) { throw "Switch '$Id' not found." }

    switch ($s.Type) {
        'Toggle' {
            $new = if ($PSBoundParameters.ContainsKey('State')) { [bool]$State } else { -not [bool]$s.State }
        }
        'Choice' {
            if (-not $PSBoundParameters.ContainsKey('State')) { throw "Must supply -State for Choice type." }
            $new = $State
        }
        default {
            $new = if ($PSBoundParameters.ContainsKey('State')) { $State } else { -not [bool]$s.State }
        }
    }

    $s.State = $new
    return $s.State
}

function private:Save-SwitchStates {
    param([string]$Path = $script:SwitchSavePath)
    if ($Path) {
        $st = $script:ActiveMenuSwitches | Select-Object Id, State
        try {
            # Ensure directory exists
            New-Item -Path (Split-Path $Path) -ItemType Directory -Force | Out-Null
            # Save switches
            $st | ConvertTo-Json -Depth 3 | Out-File -FilePath $Path -Encoding UTF8 -Force
            return $true
        } catch {
            Write-Warning "Could not save switch states to $Path"
            return $false
        }
    }
}

function private:Load-SwitchStates {
    param([string]$Path = $script:SwitchSavePath)
    if ($Path -and (Test-Path $Path)) {
        try {
            $json = Get-Content -Raw -Path $Path | ConvertFrom-Json
            foreach ($entry in $json) {
                $s = private:Get-SwitchById -Id $entry.Id
                if ($s) {
                    if ($s.Type -eq 'Toggle') {
                        $s.State = [bool]$entry.State
                    } else {
                        $s.State = $entry.State
                    }
                }
            }
        } catch {
            Write-Warning "Could not load switch states from $Path. Using defaults."
        }
    }
    return $script:ActiveMenuSwitches
}
#endregion
#==========================================#
#region * Private: Core Helpers *
#==========================================#
function private:Write-MenuColor {
    <#
    .SYNOPSIS
        (Private Helper) Writes multi-segmented, aligned, and leveled text.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position=0)][AllowEmptyCollection()][string[]] $Message,
        [Parameter(Position=1)][ConsoleColor[]]                                  $Color = @('White'),
        [Parameter(Position=2)][ConsoleColor[]]                        $BackgroundColor = @(),
        [ValidateSet('Left','Center','Right')][string]                           $Align = 'Left',
        [int]                                                                    $Width = $null,
        [ValidateSet('Info','Success','Warning','Error','Debug','Muted','Action','Input')][string] $Level,
        [switch]                                                             $NoNewline
    )

    begin {
        try { if (-not $Width) { $Width = $Host.UI.RawUI.BufferSize.Width } } catch { if (-not $Width) { $Width = [Console]::WindowWidth } }

        $levelMap = @{
            Info    = @{ FG = $private:DefaultMenuTheme.PromptInfoColor;    BG = $null }
            Success = @{ FG = $private:DefaultMenuTheme.PromptSuccessColor; BG = $null }
            Warning = @{ FG = $private:DefaultMenuTheme.PromptWarningColor; BG = $null }
            Error   = @{ FG = $private:DefaultMenuTheme.PromptErrorColor;   BG = $null }
            Debug   = @{ FG = $private:DefaultMenuTheme.PromptMutedColor;   BG = $null }
            Muted   = @{ FG = $private:DefaultMenuTheme.PromptMutedColor;   BG = $null }
            Action  = @{ FG = $private:DefaultMenuTheme.PromptActionColor;  BG = $null }
            Input   = @{ FG = $private:DefaultMenuTheme.PromptInputColor;   BG = $null }
        }

        if ($PSBoundParameters.ContainsKey('Level')) {
            if (-not $PSBoundParameters.ContainsKey('Color') -or -not $Color) { $Color = ,$levelMap[$Level].FG }
            if (-not $PSBoundParameters.ContainsKey('BackgroundColor') -and $levelMap[$Level].BG) { $BackgroundColor = ,$levelMap[$Level].BG }
        }

        if (-not $Message) { $Message = @('') }

        if ($Color.Count -eq 1 -and $Message.Count -gt 1) { $Color = ,$Color * $Message.Count }
        if ($Color.Count -ne 1 -and $Color.Count -ne $Message.Count) {
            $Color = (,$Color + ,('White' * ($Message.Count - $Color.Count)))[0..($Message.Count-1)]
        }

        if ($BackgroundColor.Count -eq 1 -and $Message.Count -gt 1) { $BackgroundColor = ,$BackgroundColor * $Message.Count }
        if ($BackgroundColor.Count -ne 0 -and $BackgroundColor.Count -ne $Message.Count) {
            $BackgroundColor = @()
        }

        for ($i=0; $i -lt $Color.Count; $i++) {
            try { $Color[$i] = [ConsoleColor]$Color[$i] } catch { $Color[$i] = [ConsoleColor]::White }
        }
        for ($i=0; $i -lt $BackgroundColor.Count; $i++) {
            try { $BackgroundColor[$i] = [ConsoleColor]$BackgroundColor[$i] } catch { $BackgroundColor[$i] = $null }
        }
    }

    process {
        $plain = ($Message -join '')
        $totalLen = [Math]::Max(0, $plain.Length)
        switch ($Align) {
            'Left'   { $padLeft = 0 }
            'Center' { $padLeft = [Math]::Max(0, [int](($Width - $totalLen) / 2)) }
            'Right'  { $padLeft = [Math]::Max(0, $Width - $totalLen) }
        }

        if ($padLeft -gt 0) { Write-Host (' ' * $padLeft) -NoNewline }

        for ($i = 0; $i -lt $Message.Count; $i++) {
            $seg = [string]$Message[$i]
            if ($BackgroundColor.Count -gt 0) {
                Write-Host $seg -ForegroundColor $Color[$i] -BackgroundColor $BackgroundColor[$i] -NoNewline
            } else {
                Write-Host $seg -ForegroundColor $Color[$i] -NoNewline
            }
        }

        if (-not $NoNewline) {
            Write-Host
        }
    }
}

function private:Test-SupportsRawUI {
    try {
        return $Host.UI.RawUI.CursorVisible -ne $null -and $Host.UI.RawUI.CanSetCursorPosition
    } catch {
        return $false
    }
}

function private:Hide-Cursor {
    if (private:Test-SupportsRawUI) {
        $Host.UI.RawUI.CursorVisible = $false
    }
}

function private:Show-Cursor {
    if (private:Test-SupportsRawUI) {
        $Host.UI.RawUI.CursorVisible = $true
    }
}

function private:Get-MenuTitle {
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
#endregion
#==========================================#
#region * Themed Menu *
#==========================================#
function private:Show-Header {
    [CmdletBinding()]
    param(
        [string]$Title,
        [string[]]$Subtitle,
        [MenuTheme]$Theme = $private:DefaultMenuTheme
    )

    if (-not $Theme) { $Theme = $private:DefaultMenuTheme }
    Clear-Host
    
    # --- MODIFIED: Integrate Switch Status ---
    $finalTitle = if ([string]::IsNullOrWhiteSpace($Title)) { (private:Get-MenuTitle) } else { "📦 $Title" }
    try { $debug = [bool](private:Get-SwitchById -Id 'D').State } catch { $debug = $false }
    try { $dryRun = [bool](private:Get-SwitchById -Id 'R').State } catch { $dryRun = $false }
    $debugText = if ($debug) { '[DEBUG]' } else { '' }
    $dryRunText = if ($dryRun) { '[DRY-RUN]' } else { '' }
    $switchText = ($debugText, $dryRunText | Where-Object { $_ }).Trim() -join ' '
    if ($switchText) {
        $finalTitle = "$finalTitle $switchText"
    }
    # --- End Modification ---

    try {
        $width = $Host.UI.RawUI.WindowSize.Width - 1
        if ($width -lt 20) { $width = 80 }
    } catch {
        $width = 80
    }

    $lineLength = [Math]::Max($finalTitle.Length + 4, [Math]::Min(($width - 4), $finalTitle.Length + 4))
    $spaceline = '=' * $lineLength
    $underline = '─' * $lineLength

    private:Write-MenuColor -Message $spaceline  -Color $Theme.HeaderSpacelineColor -Align Center
    private:Write-MenuColor -Message $finalTitle -Color $Theme.HeaderTitleColor     -Align Center
    private:Write-MenuColor -Message $spaceline  -Color $Theme.HeaderSpacelineColor -Align Center

    if ($Subtitle -and $Subtitle.Count -gt 0) {
        foreach ($s in $Subtitle) { if ($s) { private:Write-MenuColor -Level Muted -Message $s -Align Center } }
        private:Write-MenuColor -Level Action -Message $underline -Color $Theme.HeaderUnderlineColor -Align Center
    } else {
        private:Write-MenuColor -Level Action -Message $underline -Color $Theme.HeaderUnderlineColor -Align Center
    }
    Write-Host ""
}

function private:Show-StatusBar {
    [CmdletBinding()]
    param(
        [string]$LeftText='',
        [string]$RightText='',
        [MenuTheme]$Theme = $private:DefaultMenuTheme
    )
    if (-not $Theme) { $Theme = $private:DefaultMenuTheme }
    try {
        $width = $Host.UI.RawUI.WindowSize.Width - 1
        $left = $LeftText
        $right = $RightText
        $space = [Math]::Max(0, $width - ($left.Length + $right.Length))
        $line = $left + (' ' * $space) + $right
        $oldFg = $Host.UI.RawUI.ForegroundColor; $oldBg = $Host.UI.RawUI.BackgroundColor
        $Host.UI.RawUI.BackgroundColor = $Theme.StatusBarBgColor
        $Host.UI.RawUI.ForegroundColor = $Theme.StatusBarColor
        Write-Host $line
    } finally {
        try { $Host.UI.RawUI.BackgroundColor = $oldBg; $Host.UI.RawUI.ForegroundColor = $oldFg } catch {}
    }
}

function private:Show-Footer {
    [CmdletBinding()]
    param(
        [ConsoleColor]$BackgroundColor = 'Black',
        [ConsoleColor]$ForegroundColor = 'DarkGray',
        [switch]$Overwrite
    )

    $footer   = "User: $([Environment]::UserName) | Host: $env:COMPUTERNAME | $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

    try {
        $ui = $Host.UI.RawUI
        $width = $ui.WindowSize.Width
        $manualPadding = [math]::Max(0, [math]::Floor(($width - $footer.Length) / 2))
        if ($Overwrite) {
            $orig = $ui.CursorPosition
            $targetY = $ui.WindowSize.Height - 1
            $ui.CursorPosition = New-Object System.Management.Automation.Host.Coordinates (0), ($targetY)
            Write-Host ($(' ' * $manualPadding) + $footer).PadRight($width, ' ') -BackgroundColor $BackgroundColor -ForegroundColor $ForegroundColor
            $ui.CursorPosition = $orig
        } else {
            Write-Host ($(' ' * $manualPadding) + $footer) -BackgroundColor $BackgroundColor -ForegroundColor $ForegroundColor
        }
    } catch {}
}

function private:Get-MenuKeyAction {
    <#
    .SYNOPSIS
        (Private Helper) Reads a key and returns a menu action.
    #>
    while ($true) {
        $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        switch ($key.VirtualKeyCode) {
            38 { return 'Up' }      # Up arrow
            40 { return 'Down' }    # Down arrow
            13 { return 'Select' }  # Enter
            27 { return 'Exit' }    # Esc
            36 { return 'Home' }    # Home
            35 { return 'End' }     # End
            46 { return 'Delete' }  # Delete
            default {
                if ($key.Character -match '[bB]') { return 'Back' }
                if ($key.Character -match '[qQ]') { return 'Exit' }
            }
        }
    }
}

function private:Show-InteractiveMenu {
    <#
    .SYNOPSIS
        (Private Helper) Renders the arrow-key navigable menu.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Title,
        [Parameter(Mandatory=$true)][string[]]$Options,
        [string[]]$Subtitle,
        [MenuTheme]$Theme = $private:DefaultMenuTheme
    )

    if (-not $Theme) { $Theme = $private:DefaultMenuTheme }
    if (-not $Options -or $Options.Count -eq 0) { return $private:EXIT_CODE }

    $itemFg = $Theme.AccentColor
    $selFg  = $Theme.HighlightFg
    $selBg  = $Theme.HighlightBg

    $selectedIndex = 0
    $count = $Options.Count
    $supportsRawUI = private:Test-SupportsRawUI

    private:Hide-Cursor
    try {
        while ($true) {
            private:Show-Header -Title $Title -Subtitle $Subtitle -Theme $Theme
            $optionsStartRow = $Host.UI.RawUI.CursorPosition.Y

            for ($i = 0; $i -lt $count; $i++) {
                $optionText = $Options[$i]
                if ($i -eq $selectedIndex) {
                    $display = "$($Theme.PointerGlyph)$optionText"
                    $remainingWidth = ($Host.UI.RawUI.WindowSize.Width - 1) - $display.Length
                    if ($remainingWidth -lt 0) { $remainingWidth = 0 }
                    $display = $display + (' ' * $remainingWidth)

                    try { $Host.UI.RawUI.BackgroundColor = $selBg; $Host.UI.RawUI.ForegroundColor = $selFg } catch {}
                    Write-Host $display -NoNewline
                    try { $Host.UI.RawUI.ResetColor() } catch {}
                    Write-Host ''
                } else {
                    $display = " $optionText"
                    Write-Host $display -ForegroundColor $itemFg
                }
            }

            private:Show-StatusBar -LeftText "Item $([int]($selectedIndex + 1))/$count" -RightText (Get-Date -Format "yyyy-MM-dd HH:mm:ss") -Theme $Theme

            $action = private:Get-MenuKeyAction
            switch ($action) {
                'Up'    { $selectedIndex = ($selectedIndex - 1 + $count) % $count }
                'Down'  { $selectedIndex = ($selectedIndex + 1) % $count }
                'Home'  { $selectedIndex = 0 }
                'End'   { $selectedIndex = $count - 1 }
                'Select'{ return $selectedIndex }
                'Back'  { return $private:BACK_CODE }
                'Exit'  { return $private:EXIT_CODE }
            }

            if ($supportsRawUI) {
                try { $Host.UI.RawUI.CursorPosition = New-Object System.Management.Automation.Host.Coordinates 0 $optionsStartRow } catch {}
            } else {
                Clear-Host
            }
        }
    } finally {
        private:Show-Cursor
    }
}
#endregion
#==========================================#
#region * Public Functions for Themed Menu *
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
        [ConsoleColor]$AccentColor = 'Cyan',
        [ConsoleColor]$HighlightFg = 'Black',
        [ConsoleColor]$HighlightBg = 'White',
        [string]$PointerGlyph = '➤ ',
        [ConsoleColor]$HeaderTitleColor = 'Cyan',
        [ConsoleColor]$StatusBarColor = 'Yellow',
        [ConsoleColor]$StatusBarBgColor = 'DarkBlue'
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
        $actions = @(
            @{ Label = "Say Hello"; Action = { Write-Host "Hello!" } },
            @{ Label = "Exit"; Action = { return $private:EXIT_CODE } }
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
#endregion
#==========================================#
#region *Dashboard Menu *
#==========================================#
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
        $menu = @( @{ Key = '1'; Label = 'Start' }, @{ Key = 'Q'; Label = 'Quit' } )
        $statusBlock = {
            $svc = Get-Service -Name "MyService" -ErrorAction SilentlyContinue
            return @( @{ Name = 'Status'; Value = $svc.Status } )
        }
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
#region * Public: Switch Management Functions *
#==========================================#
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
#region * Module Export *
#==========================================#
Export-ModuleMember -Function Invoke-InteractiveMenu, `
                                Invoke-DashboardMenu, `
                                New-InteractiveMenuTheme, `
                                Get-InteractiveMenuSwitch, `
                                Set-InteractiveMenuSwitch, `
                                Save-InteractiveMenuSwitches, `
                                Load-InteractiveMenuSwitches, `
                                Reset-InteractiveMenuSwitches

# On module load, try to load saved switches
private:Load-SwitchStates | Out-Null

#endregion