#==========================================#
# Public Functions
#==========================================#
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

function Confirm-YesNo {
    <#
    .SYNOPSIS
        Prompts the user for a Yes/No answer, defaulting to 'No' on non-Y/y input.
    .PARAMETER Message
        The message displayed to the user. Defaults to 'Proceed?'.
    .PARAMETER ConfirmFunction
        Allows overriding the default read mechanism with a custom ScriptBlock.
    .OUTPUTS
        [bool] - $true if 'y' or 'Y' is entered, otherwise $false.
    #>
    param(
        [string]$Message = 'Proceed?',
        [ScriptBlock]$ConfirmFunction = $null
    )

    if (-not $ConfirmFunction) {
        # Default behavior: Match 'y' or 'Y'. Any other input, including empty, returns $false.
        $ConfirmFunction = { param($m) (Read-Host "$m (y/N)") -match '^(y|Y)' }
    }

    # Execute the confirmation logic.
    return & $ConfirmFunction $Message
}

function Get-CurrentLogFile {
    $datePart = Get-Date -Format "yyyyMMdd"
    return
    Join-Path -Path $LogDirectory -ChildPath "ProfileMenu_$datePart.log"
}

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

function Get-SwitchById {
    param([array]$MenuSwitches, [string]$Id)
    # Simulate the states needed for the example output: DEBUG: ON, DRY-RUN: ON, Nav: Arrow, ExecPath: TRUE
    switch ($Id) {
        'N' { return [PSCustomObject]@{ State = 'Arrow' } }
        'D' { return [PSCustomObject]@{ State = $true } }
        'R' { return [PSCustomObject]@{ State = $true } }
        'E' { return [PSCustomObject]@{ State = $true } }
        default { return [PSCustomObject]@{ State = $false } }
    }
}

function Get-YesNoChoice {
    <#
    .SYNOPSIS
        The most robust, portable method for getting a Yes/No choice using $host.UI.PromptForChoice().
    .PARAMETER Message
        The main question displayed to the user.
    .PARAMETER Caption
        The title bar text for the prompt window.
    .OUTPUTS
        [bool] - $true if 'Yes' is selected, $false if 'No' is selected.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        [string]$Caption = 'Confirmation'
    )

    # Define the choices with mnemonics (&Yes, &No)
    $choiceYes = [System.Management.Automation.Host.ChoiceDescription]::new('&Yes', 'Select Yes.')
    $choiceNo  = [System.Management.Automation.Host.ChoiceDescription]::new('&No', 'Select No.')
    $choices = [System.Management.Automation.Host.ChoiceDescription[]]($choiceYes, $choiceNo)

    # Prompt the user. The '1' sets the default choice index (0=Yes, 1=No)
    $defaultChoice = 1
    $choiceIndex = $host.UI.PromptForChoice($Caption, $Message, $choices, $defaultChoice)

    # Return $true if the user selected index 0 ('Yes')
    return $choiceIndex -eq 0
}

function Hide-Cursor {
    <#
      .SYNOPSIS
          Hides the console cursor if RawUI is supported.
      .DESCRIPTION
          Sets the console cursor visibility to false, if the host supports RawUI.
    #>
    if (Test-SupportsRawUI) {
        $Host.UI.RawUI.CursorVisible = $false
    }
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

function Load-Context {
    param([string]$Path = (Join-Path $env:TEMP 'menu-context.json'))
    if (Test-Path $Path) { return Get-Content $Path -Raw | ConvertFrom-Json } else { return $null }
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
        'UpArrow'    { $intent = 'Up' }
        'DownArrow'  { $intent = 'Down' }
        'Enter'      { $intent = 'Enter' }
        'Escape'     { $intent = 'Escape' }
        'Q'          { $intent = 'Quit' }
        default      { }
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
        Key        = $raw.Key
        KeyChar    = $char
        Intent     = $intent
        SwitchId   = $switchId
        Number     = $number
        RawKeyInfo = $raw
    }
}

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

function Read-YesNo {
    <#
    .SYNOPSIS
        Prompts the user for a Yes/No answer and forces a valid choice.
    .PARAMETER Message
        The message displayed to the user.
    .OUTPUTS
        [bool] - $true if 'y' or 'Y' is entered, $false if 'n' or 'N' is entered.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )
    while ($true) {
        $response = Read-Host -Prompt "$Message (Y/N)"
        if ($response -match '^[Yy]$') { return $true }
        if ($response -match '^[Nn]$') { return $false }

        # NOTE: Replacing custom 'Write-Color' with the standard 'Write-Warning' for portability.
        Write-Warning "Invalid input. Please enter Y or N."
    }
}

function Register-Action {
    param([string]$Id, [ScriptBlock]$Script)
    if (-not $Id) { throw 'Id required' }
    $ActionRegistry[$Id] = $Script
}

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
    #region 1. Determine execution path visibility state
    try { $showExecPath = [bool](Get-SwitchById -MenuSwitches $MenuSwitches -Id 'E').State   } catch { $showExecPath  = $false }
    #endregion
    #region 2. Render Header
    Show-Header -Title $Title -ScriptDir $ScriptDir -MenuSwitches $MenuSwitches -ShowExecPath $showExecPath
    #endregion
    #region 3. Render Menu Items
    for ($i = 0; $i -lt $MenuItems.Count; $i++) {
        $itemName = $MenuItems[$i].Name

        # Color settings for selected text (used in both modes)
        $selectedTextFg = $GlobalConfig.SelectedTextColor
        $selectedTextBg = $GlobalConfig.SelectedTextBg

        if ($Mode -eq 'Arrow') {
            if ($i -eq $Selected) {
                # Selected: Token '->' (2 chars) + space separator (1 char) = 3 chars offset.
                Show-CenteredLine `
                    -Token $GlobalConfig.SelectedToken `
                    -TokenColored:$true `
                    -Text $itemName `
                    -TokenFg $GlobalConfig.SelectedTokenColor `
                    -TokenBg $GlobalConfig.SelectedTokenBg `
                    -TextFg $selectedTextFg `
                    -TextBg $selectedTextBg `
                    -TextColored:$true
            } else {
                # Unselected: Use 3 spaces ('   ') as the token to match the 3-char offset, aligning text with the selected item's text.
                Show-CenteredLine `
                    -Token '   ' `
                    -TokenColored:$false `
                    -Text $itemName `
                    -TextColored:$false # Default to White on Black
            }
        } else { # Numeric Mode
            $label = ('{0}:' -f ($i + 1)).PadRight(3)

            if ($i -eq $Selected) {
                # Selected in Numeric mode: Highlight token and text
                Show-CenteredLine `
                    -Token $label `
                    -TokenColored:$true `
                    -Text $itemName `
                    -TokenFg $GlobalConfig.SelectedTokenColor `
                    -TokenBg $GlobalConfig.SelectedTokenBg `
                    -TextFg $selectedTextFg `
                    -TextBg $selectedTextBg `
                    -TextColored:$true
            } else {
                # Unselected in Numeric mode: Highlight token, plain text
                Show-CenteredLine `
                    -Token $label `
                    -TokenColored:$true `
                    -Text $itemName `
                    -TokenFg $GlobalConfig.UnselectedTokenColor `
                    -TokenBg $GlobalConfig.UnselectedTokenBg `
                    -TextColored:$false # Default to White on Black
            }
        }
    }
    #endregion
    #region 4. Separator line above status bar (Matching the visual example)
    $separatorLine = $GlobalConfig.UnderLineChar * 45
    Show-CenteredLine -Token '' -TokenColored:$false -Text $separatorLine -TextColored:$false -TextFg $GlobalConfig.SeparatorColor
    #endregion
    #region 5. Status bar (with colored ON/OFF states)
    Show-StatusBar -ScriptDir $ScriptDir -MenuSwitches $MenuSwitches
    #endregion
    #region 6. Footer (Contains the long separator and usage text)
    Show-Footer -Mode $Mode -MenuItems $MenuItems -MenuSwitches $MenuSwitches
    #endregion
}

function Save-Context {
    param([psobject]$Context, [string]$Path = (Join-Path $env:TEMP 'menu-context.json'))
    $Context | ConvertTo-Json -Depth 5 | Set-Content -Path $Path -Encoding UTF8
}

function Save-SwitchStates {
    param([array]$MenuSwitches, [string]$Path)
    if ($Path) { $st = $MenuSwitches | Select-Object Id, State
        try { $st | ConvertTo-Json -Depth 3 | Out-File -FilePath $Path -Encoding UTF8 -Force ;              return $true }
        catch { Write-Host "Warning: Could not save switch states to $Path" -ForegroundColor DarkYellow ;   return $false }
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

function Show-CenteredText {
    <#
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
    #>
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

function Show-Cursor {
    <#
      .SYNOPSIS
          Shows the console cursor if RawUI is supported.
      .DESCRIPTION
          Sets the console cursor visibility to true, if the host supports RawUI.
    #>
    if (Test-SupportsRawUI) {
        $Host.UI.RawUI.CursorVisible = $true
    }
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
        $footerText = "Press number (1-$numItems) to run immediately, Q/ESC to quit. $switchHints"
    }
    $pad = if ($GlobalConfig.FooterPadding) { [int]$GlobalConfig.FooterPadding } else { 2 }
    $spacelineChar  = if ($GlobalConfig.SpaceLineChar) { $GlobalConfig.SpaceLineChar } else { '=' }

    $lineLength = [Math]::Max(10, ($footerText.Length + ($pad * 2)))
    $spaceline = ($spacelineChar * $lineLength)
    # $underline = ($underlineChar * [Math]::Min(80, [Math]::Max(10, $footerText.Length)))

    Show-CenteredLine -Token '' -TokenColored:$false -Text $spaceline -TextColored:$false -TextFg $GlobalConfig.SpaceLineColor
    Show-CenteredLine -Token '' -TokenColored:$false -Text $footerText -TextColored:$false -TextFg $GlobalConfig.FooterFgColor
    Write-Host ''
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
        [Parameter(Mandatory=$false)][array]$MenuSwitches = @(),
        [Parameter(Mandatory=$false)][bool]$showExecPath = $false
    )
    if (-not $Title) {
        try { $derived = Get-MenuTitle -Path $ScriptDir
            if ($derived) { $Title = $derived } else { $Title = Split-Path -Leaf $ScriptDir }
        } catch { $Title = Split-Path -Leaf $ScriptDir }
    }
    $pad            = if ($GlobalConfig.HeaderPadding) { [int]$GlobalConfig.HeaderPadding } else { 2 }
    $sepChar        = if ($GlobalConfig.SeparatorChar) { $GlobalConfig.SeparatorChar } else { '─' }
    $spacelineChar  = if ($GlobalConfig.SpaceLineChar) { $GlobalConfig.SpaceLineChar } else { '=' }

    $titleDisplay = ($GlobalConfig.HeaderIcon + ' ' + $Title).Trim()
    $lineLength = [Math]::Max(10, ($titleDisplay.Length + ($pad * 2)))
    $spaceline = ($spacelineChar * $lineLength)
    $underline  = ($sepChar * $lineLength)

    Show-CenteredLine -Token '' -TokenColored:$false -Text $Title     -TextColored:$true -TextFg $GlobalConfig.HeaderTitleColor
    Show-CenteredLine -Token '' -TokenColored:$false -Text $spaceline -TextColored:$true -TextFg $GlobalConfig.SpaceLineColor

    if ($ShowExecPath) {
        $displayPath = ("Execution path: $ScriptDir")
        Show-CenteredLine -Token '' -TokenColored:$false -Text $displayPath -TextColored:$true -TextFg $GlobalConfig.InfoColor
        $longSeparator = $sepChar * [Math]::Max(30, $displayPath.Length + 10)
        Show-CenteredLine -Token '' -TokenColored:$false -Text $longSeparator  -TextColored:$true -TextFg $GlobalConfig.SeparatorColor
    } elseif ($Subtitle) {
        Show-CenteredLine -Token '' -TokenColored:$false -Text $Subtitle   -TextColored:$true -TextFg $GlobalConfig.HeaderSubtitleColor
        Show-CenteredLine -Token '' -TokenColored:$false -Text $underline  -TextColored:$true -TextFg $GlobalConfig.SeparatorColor
    } else {
        Show-CenteredLine -Token '' -TokenColored:$false -Text $underline  -TextColored:$true -TextFg $GlobalConfig.SeparatorColor
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

function Test-SupportsRawUI {
    <#
      .SYNOPSIS
          Tests if the current host supports RawUI operations.
      .DESCRIPTION
          Checks if the host's UI supports RawUI features like cursor visibility
          and position manipulation.
      .OUTPUTS
          [bool]
          Returns $true if RawUI is supported, otherwise $false.
      .EXAMPLE
          if (Test-SupportsRawUI) {
              Write-Host "RawUI is supported."
          } else {
              Write-Host "RawUI is not supported."
          }
    #>
    try {
        return $Host.UI.RawUI.CursorVisible -ne $null -and $Host.UI.RawUI.CanSetCursorPosition
    } catch {
        return $false
    }
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

function Write-HostWithColor {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        [ConsoleColor]$ForegroundColor = 'White',
        [ConsoleColor]$BackgroundColor = 'Black'
    )
    Write-Host $Message -ForegroundColor $ForegroundColor -BackgroundColor $BackgroundColor
}

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

# SIG # Begin signature block
# MIIFvwYJKoZIhvcNAQcCoIIFsDCCBawCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCB26GFXFzl1Jf7c
# br9MrabaHAOXm4tPNLQZF70BcOaBu6CCAyYwggMiMIICCqADAgECAhBTL0G9/1qW
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
# LwYJKoZIhvcNAQkEMSIEIKoiKhZt2Ti42odLh+W0awxsZ3yJ/pOirYarX27RFw89
# MA0GCSqGSIb3DQEBAQUABIIBABNOm04QGEsMFzPZc6pLeD0A6/d1AjlINFb0tmSC
# 8bhiovKKJipUvlrlBQq7KDbo/AqNM2kP5+j7Fn8VvxjGf0rLpmAO+O5rOUZhvfEw
# 5VXISXrmTwpnMqVkp/YJecdnsVQ+g3lL3+8MKdJKOy6lQIawKS6tqhu4tDxm+tVl
# Qx6g5bkni4z+4f+cKA3LCTdJlHAjAzlISZRFogV2S2PhlRGs2X2WUsGOnnXhRYZ1
# LUcLlp6dVptrZlWfs+K1UK0zumglf0iW2g4/F0459a8pD1fnli2ysY7XkhHxDDiC
# 0VSJdD7y93QHvIC2w8BRAb/oXMF4qYqnyob4WqkR4pcbJx4=
# SIG # End signature block
