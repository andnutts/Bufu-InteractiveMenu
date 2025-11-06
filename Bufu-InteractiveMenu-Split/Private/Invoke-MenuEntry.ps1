function Invoke-MenuEntry {
    param(
        [Parameter(Mandatory)][object]$Entry,
        [Parameter(Mandatory)][string]$ScriptDir,
        [Parameter(Mandatory)][array]$MenuSwitches
    )
    $debugFlag = (Get-SwitchById -MenuSwitches $MenuSwitches -Id 'D').State
    $dryRunFlag = (Get-SwitchById -MenuSwitches $MenuSwitches -Id 'R').State

    if ($dryRunFlag) {
        Write-Host "DRY RUN MODE: Command not executed." -ForegroundColor Yellow
        # Check if it's a file entry or action entry for logging
        if ($Entry.PSObject.Properties['File']) {
            Write-Host "Target: $($Entry.File) (Type: $($Entry.Type))`n" -ForegroundColor Yellow
        } elseif ($Entry.PSObject.Properties['Action']) {
            Write-Host "Action: $($Entry.Name)`n" -ForegroundColor Yellow
        }
        return $true
    }

    # --- Check for ScriptBlock Action ---
    if ($Entry.PSObject.Properties['Action'] -and $Entry.Action -is [ScriptBlock]) {
        Write-Host "`n[Running: $($Entry.Name)...]`n" -ForegroundColor Yellow
        try {
            # Invoke the scriptblock. Pass MenuSwitches as an argument for context if needed,
            # or just invoke directly.
            $result = & $Entry.Action.Invoke()
            # Check for 'quit' signal from scriptblock
            if ($result -eq 'quit') {
                return 'quit' # Propagate quit signal
            }
            return $true
        } catch {
            Write-Colored -Text "`nERROR during action '$($Entry.Name)': $($_.Exception.Message)`n" -Fg 'White' -Bg 'DarkRed'
            return $false
        }
    }

    # --- Existing File-based logic ---
    if (-not $Entry.PSObject.Properties['File']) {
        Write-Warning "Menu entry '$($Entry.Name)' has no 'Action' or 'File' defined."
        return $false
    }

    $scriptPath = Join-Path -Path $ScriptDir -ChildPath $Entry.File
    if (-not (Test-Path $scriptPath)) {
        Write-Colored -Text "Script not found: $scriptPath`n" -Fg 'White' -Bg 'DarkRed'
        return $false
    }
    
    Write-Host "`n[Running: $($Entry.Name)...]`n" -ForegroundColor Yellow

    switch ($Entry.Type) {
        'GUI' {
            Write-Host "Starting GUI script in new process..." -ForegroundColor DarkCyan
            Start-Process -FilePath "python" -ArgumentList @($scriptPath) -ErrorAction SilentlyContinue
        }
        'CMD' {
            Write-Host "Executing CMD script inline..." -ForegroundColor DarkCyan
            $argList = @($scriptPath)
            if ($debugFlag) { $argList += '--verbose' }
            & python @argList
        }
        'PS1' {
            Write-Host "Executing PowerShell script inline..." -ForegroundColor DarkCyan
            . $scriptPath
        }
        default {
            Write-Host "Starting generic process..." -ForegroundColor DarkCyan
            Start-Process -FilePath "python" -ArgumentList @($scriptPath) -ErrorAction SilentlyContinue
        }
    }
    return $true
}
