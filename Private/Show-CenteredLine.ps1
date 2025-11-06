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