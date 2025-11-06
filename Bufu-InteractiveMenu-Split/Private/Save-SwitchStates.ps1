function Save-SwitchStates {
    param([array]$MenuSwitches, [string]$Path)
    if ($Path) { $st = $MenuSwitches | Select-Object Id, State
        try { $st | ConvertTo-Json -Depth 3 | Out-File -FilePath $Path -Encoding UTF8 -Force ;              return $true }
        catch { Write-Host "Warning: Could not save switch states to $Path" -ForegroundColor DarkYellow ;   return $false }
    }
}