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