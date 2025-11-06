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
