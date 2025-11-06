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
