function Show-Header {
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
