function Show-InteractiveMenu {
    <#
        .SYNOPSIS
            Displays an interactive, centralized, and color-coded console menu.
        .DESCRIPTION
            This function renders a list of menu items and switches, allowing
            the user to navigate using arrow keys or numeric input, toggle
            features, and execute associated scripts or scriptblocks.
        .PARAMETER MenuData
            A Hashtable defining the menu options. Keys are used for stable ordering.
            Each value must be a PSCustomObject with a 'Name' property.
            It should also have *either* an 'Action' property (a ScriptBlock)
            *or* 'File' and 'Type' properties for launching external files.
            Example (ScriptBlock): @{'1' = @{Name='Run Task'; Action={...}}}
            Example (File): @{'2' = @{Name='Convert'; File='script.py'; Type='CMD'}}
        .PARAMETER MenuSwitches
            An optional array of PSCustomObject switches. If not provided, the default
            (Debug, Navigation, Dry-Run) set is used. Each switch must have Id, Name, State, and Type.
        .PARAMETER Title
            The title displayed at the top of the menu.
        .PARAMETER ScriptDir
            The directory containing the files specified in MenuData (if using file-based entries).
        .PARAMETER EnablePersistence
            If specified, the states of the switches (D, N, R, etc.) are saved to a
            JSON file in the user's profile directory and loaded on next execution.
        .EXAMPLE
            $MyMenu = @{
                '1' = [PSCustomObject]@{ Name = 'Generate Report'; Action = { Write-Host "Report..." } }
                '2' = [PSCustomObject]@{ Name = 'Launch GUI Tool'; File = 'gui.py'; Type = 'GUI' }
            }
            Show-InteractiveMenu -MenuData $MyMenu -ScriptDir "C:\MyTools\Scripts" -EnablePersistence
    #>
    param(
        [Parameter(Mandatory)][object]$MenuData,
        [array]$MenuSwitches = $DefaultSwitches,
        [string]$Title,
        [string]$SubTitle,
        [string]$ScriptDir = (Get-Location).Path,
        [switch]$EnablePersistence
    )
    #region 1. Prepare persistence path if enabled
    $persistencePath = $null
    if ($EnablePersistence) {
        $persistencePath = "$env:USERPROFILE\PowershellMenuStates.json"
        Load-SwitchStates -MenuSwitches $MenuSwitches -Path $persistencePath | Out-Null
    }
    #endregion
    #region 2. Normalize MenuData to ordered $menuItems
    $menuItems = @()

    if ($MenuData -is [System.Collections.Hashtable]) {
        $menuKeys = $MenuData.Keys | Sort-Object
        foreach ($k in $menuKeys) {
            $item = $MenuData[$k]
            if (-not $item.PSObject.Properties['Key']) {
                $item | Add-Member -MemberType NoteProperty -Name 'Key' -Value $k -PassThru | Out-Null
            } else {
                $item.Key = $k
            }
            $menuItems += $item
        }
    } elseif ($MenuData -is [System.Array] -or $MenuData -is [System.Collections.IEnumerable]) {
        # Accept arrays or any enumerable (ordered). Use index as Key if not present.
        $i = 0
        foreach ($item in $MenuData) {
            if (-not $item.PSObject.Properties['Key']) {
                $item | Add-Member -MemberType NoteProperty -Name 'Key' -Value $i -PassThru | Out-Null
            } else {
                $item.Key = $item.Key
            }
            $menuItems += $item
            $i++
        }
    } else {
        throw "Unsupported MenuData type: $($MenuData.GetType().FullName). Provide a hashtable or array of menu items."
    }

    if ($menuItems.Count -eq 0) {
        Write-Host "Error: MenuData is empty." -ForegroundColor Red
        return
    }
    #endregion
    #region 3. Get initial state for local variables
    $selected = 0
    $quit = $false
    #endregion
    #region 4. Main Menu Loop
    do {
        $mode = (Get-SwitchById -MenuSwitches $MenuSwitches -Id 'N').State
        #region 4a. Render the menu
        Render-FullMenu -Selected $selected -Mode $mode -MenuSwitches $MenuSwitches -MenuItems $menuItems -Title $Title -ScriptDir $ScriptDir
        #endregion
        #region 4b. Read Key Input
        $keyInfo = Read-MenuKey -MenuSwitches $MenuSwitches -Mode $mode
        $actionTaken = $false
        #endregion
        #region 4c. Handle Key input
        try {
            switch ($keyInfo.Intent) {
                'Up' {
                    $selected = ($selected - 1) % $menuItems.Count
                    if ($selected -lt 0) { $selected = $menuItems.Count - 1 }
                    $actionTaken = $true
                }
                'Down' {
                    $selected = ($selected + 1) % $menuItems.Count
                    $actionTaken = $true
                }
                'Enter' {
                    $entry = $menuItems[$selected]
                    $invokeResult = Invoke-MenuEntry -Entry $entry -ScriptDir $ScriptDir -MenuSwitches $MenuSwitches
                    if ($invokeResult -eq 'quit') { $quit = $true }
                    else { Read-Host "`nPress [Enter] to return to menu..." | Out-Null }
                    $actionTaken = $true
                }
                'Number' {
                    $index = $keyInfo.Number - 1
                    if ($index -ge 0 -and $index -lt $menuItems.Count) {
                        $entry = $menuItems[$index]
                        $invokeResult = Invoke-MenuEntry -Entry $entry -ScriptDir $ScriptDir -MenuSwitches $MenuSwitches
                        $selected = $index
                        if ($invokeResult -eq 'quit') { 
                            $quit = $true 
                        } else {
                            Read-Host "`nPress [Enter] to return to menu..." | Out-Null
                        }
                        $actionTaken = $true
                    }
                }
                'Switch' {
                    $s = Get-SwitchById -MenuSwitches $MenuSwitches -Id $keyInfo.SwitchId
                    if ($s.Type -eq 'Toggle') {
                        Set-SwitchState -MenuSwitches $MenuSwitches -Id $keyInfo.SwitchId
                        $actionTaken = $true
                    } elseif ($s.Type -eq 'Choice' -and $keyInfo.SwitchId -eq 'N') {
                        $current = $s.State
                        $new = if ($current -eq 'Arrow') { 'Numeric' } else { 'Arrow' }
                        Set-SwitchState -MenuSwitches $MenuSwitches -Id 'N' -State $new
                        $actionTaken = $true
                    }
                }
                'Quit' { $quit = $true; $actionTaken = $true }
                'Escape' { $quit = $true; $actionTaken = $true }
                default { }
            }
            if ($EnablePersistence -and $actionTaken -and $keyInfo.Intent -in @('Switch', 'Quit', 'Escape')) {
                 Save-SwitchStates -MenuSwitches $MenuSwitches -Path $persistencePath | Out-Null
            }
        #endregion
        #region 4d. Handle Errors
        } catch {
            Write-Colored -Text "`nERROR: $($_.Exception.Message)`n" -Fg 'White' -Bg 'DarkRed'
            Read-Host "`nPress [Enter] to continue..." | Out-Null
        }
        #endregion
    } while (-not $quit)
    #endregion
    #region 5. Cleanup
    [Console]::ResetColor()
    try { Clear-Host } catch {}
    #endregion
}