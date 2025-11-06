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