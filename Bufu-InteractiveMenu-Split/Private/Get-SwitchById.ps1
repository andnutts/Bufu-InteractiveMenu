function Get-SwitchById {
    param([array]$MenuSwitches, [string]$Id)
    # Simulate the states needed for the example output: DEBUG: ON, DRY-RUN: ON, Nav: Arrow, ExecPath: TRUE
    switch ($Id) {
        'N' { return [PSCustomObject]@{ State = 'Arrow' } }
        'D' { return [PSCustomObject]@{ State = $true } }
        'R' { return [PSCustomObject]@{ State = $true } }
        'E' { return [PSCustomObject]@{ State = $true } }
        default { return [PSCustomObject]@{ State = $false } }
    }
}
