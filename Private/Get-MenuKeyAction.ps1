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