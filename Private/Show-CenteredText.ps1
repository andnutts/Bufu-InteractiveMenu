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