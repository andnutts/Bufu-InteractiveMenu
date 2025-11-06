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