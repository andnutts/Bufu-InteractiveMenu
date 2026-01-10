# --- Dynamic Hyper-V Router Menu Script (improved) ---
# Requires: InteractiveMenu.psm1 (menu runner)
# Drop this file next to InteractiveMenu.psm1
# ==========================================
#region * Import Interactive Menu Module *
# ==========================================
$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$MenuModule = Join-Path $ScriptPath 'InteractiveMenu.psm1'
if (Test-Path $MenuModule) {
    . $MenuModule
    Write-Host "[OK] InteractiveMenu.psm1 module loaded." -ForegroundColor Green
} else {
    Write-Error "InteractiveMenu.psm1 not found in script directory. Exiting."
    return
}
#endregion
#
# ==========================================
#region * Configurable settings *
# ==========================================
$RefreshSeconds = 2
$VMNamePattern = 'OpenWrt|DD-WRT'
$VMRoot = Join-Path $PSScriptRoot 'VMs'
$qemuImgPath = 'qemu-img'    # set full path if qemu-img is not on PATH
$RunUntilCancelled = $true
# Set $DryRun to $true to queue actions for confirmation, $false to execute immediately
$DryRun = $true
#endregion
# ==========================================
#region * Helper Functions *
# ==========================================
function Ensure-Admin {
    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Warning 'This script should be run as Administrator for full Hyper-V functionality.'
    }
}
Ensure-Admin

function Get-RouterVMs {
    # Filters VMs based on the configured pattern
    Get-VM | Where-Object { $_.Name -match $VMNamePattern }
}

function Get-ImageStatus {
    param([string]$FilePath)
    if (Test-Path $FilePath) { 'Built' } else { 'Missing' }
}
#endregion
# ==========================================
#region * what-if report and execution *
# ==========================================
$WhatIfLogPath = Join-Path $PSScriptRoot 'whatif-log.txt'

$WhatIfQueue = [System.Collections.Generic.List[hashtable]]::new()

function Log-WhatIf {
    param(
        [string]$ActionType,    # e.g., 'Start-VM', 'Stop-VM', 'qemu-convert'
        [hashtable]$Details     # arbitrary key/value details
    )
    $entry = @{
        Timestamp = (Get-Date).ToString('u')
        Action    = $ActionType
        Details   = $Details
    }
    $WhatIfQueue.Add($entry)
    $text = "{0} | {1} | {2}" -f $entry.Timestamp, $entry.Action, ($entry.Details.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" } ) -join ';'
    Add-Content -Path $WhatIfLogPath -Value $text
}

function Clear-WhatIf {
    $WhatIfQueue.Clear()
    if (Test-Path $WhatIfLogPath) { Remove-Item $WhatIfLogPath -Force }
}

function Show-WhatIfSummary {
    if ($WhatIfQueue.Count -eq 0) {
        Write-Host "No pending what-if actions." -ForegroundColor DarkGray
        return
    }
    Write-Host "Pending What-If Actions:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $WhatIfQueue.Count; $i++) {
        $e = $WhatIfQueue[$i]
        Write-Host ("[{0}] {1} @ {2}" -f ($i+1), $e.Action, $e.Timestamp)
        $e.Details.GetEnumerator() | ForEach-Object { Write-Host "     $($_.Key): $($_.Value)" }
    }
    Write-Host ""
    Write-Host "A copy of the what-if report was appended to $WhatIfLogPath" -ForegroundColor DarkGray
}

function Confirm-And-Execute-WhatIf {
    if ($WhatIfQueue.Count -eq 0) {
        Write-Host "No what-if actions to execute." -ForegroundColor DarkGray
        return
    }

    Show-WhatIfSummary
    $confirm = Read-Host 'Execute all queued actions now? Type YES to proceed'
    if ($confirm -ne 'YES') {
        Write-Host 'Execution cancelled. No changes made.' -ForegroundColor Yellow
        return
    }

    # Temporarily override DryRun for actual execution
    $OriginalDryRun = $DryRun
    $script:DryRun = $false

    # Execute actions sequentially; collect failures
    $failures = @()
    foreach ($entry in $WhatIfQueue) {
        Write-Host "Executing $($entry.Action) for $($entry.Details.VMName$entry.Details.Dest):" -ForegroundColor White
        switch ($entry.Action) {
            'Start-VM' {
                try {
                    Start-VM -VMName $entry.Details.VMName -Passthru | Select-Object Name, State | Format-Table -AutoSize
                } catch {
                    $failures += @{ Entry = $entry; Error = $_.Exception.Message }
                    Write-Error "Start-VM failed: $($_.Exception.Message)"
                }
            }
            'Stop-VM' {
                try {
                    Stop-VM -VMName $entry.Details.VMName -TurnOff -Passthru | Select-Object Name, State | Format-Table -AutoSize
                } catch {
                    $failures += @{ Entry = $entry; Error = $_.Exception.Message }
                    Write-Error "Stop-VM failed: $($_.Exception.Message)"
                }
            }
            'Restart-VM' {
                try {
                    Restart-VM -VMName $entry.Details.VMName -Force -Passthru | Select-Object Name, State | Format-Table -AutoSize
                } catch {
                    $failures += @{ Entry = $entry; Error = $_.Exception.Message }
                    Write-Error "Restart-VM failed: $($_.Exception.Message)"
                }
            }
            'qemu-convert' {
                try {
                    # Call the now *non-dry-run* Invoke-QemuConvert
                    if (-not (Invoke-QemuConvert -Source $entry.Details.Source -Dest $entry.Details.Dest)) {
                        $failures += @{ Entry = $entry; Error = 'qemu-img failed' }
                    }
                } catch {
                    $failures += @{ Entry = $entry; Error = $_.Exception.Message }
                    Write-Error "QemuConvert failed: $($_.Exception.Message)"
                }
            }
            default {
                $failures += @{ Entry = $entry; Error = "Unknown action type: $($entry.Action)" }
            }
        }
        Start-Sleep -Milliseconds 500 # Small delay for readability
    }

    # Restore DryRun state
    $script:DryRun = $OriginalDryRun

    Write-Host ""
    if ($failures.Count -gt 0) {
        Write-Host "Some actions failed:" -ForegroundColor Red
        foreach ($f in $failures) {
            Write-Host " - $($f.Entry.Action) : $($f.Error)"
        }
    } else {
        Write-Host "All queued actions executed successfully." -ForegroundColor Green
    }

    # clear queue and log after execution
    Clear-WhatIf
    Read-Host 'Press Enter to continue'
}

function View-WhatIfLog {
    if (Test-Path $WhatIfLogPath) {
        Write-Host "Content of $WhatIfLogPath:" -ForegroundColor Cyan
        Get-Content -Path $WhatIfLogPath | Format-Table -Wrap -AutoSize
    } else {
        Write-Host "What-if log file not found at $WhatIfLogPath." -ForegroundColor Yellow
    }
    Read-Host 'Press Enter to continue'
}
#endregion
# ==========================================
#region * Invoke Functions *
# ==========================================
function Invoke-StartVM {
    param([string]$VMName)
    if ($DryRun) {
        Write-Host "[Dry-Run] Start-VM -VMName $VMName" -ForegroundColor Yellow
        Log-WhatIf -ActionType 'Start-VM' -Details @{ VMName = $VMName }
        return [pscustomobject]@{ Name = $VMName; State = 'WouldStart' }
    } else {
        Start-VM -VMName $VMName -Passthru | Select-Object Name, State
    }
}

function Invoke-StopVM {
    param([string]$VMName)
    if ($DryRun) {
        Write-Host "[Dry-Run] Stop-VM -VMName $VMName -TurnOff" -ForegroundColor Yellow
        Log-WhatIf -ActionType 'Stop-VM' -Details @{ VMName = $VMName }
        return [pscustomobject]@{ Name = $VMName; State = 'WouldStop' }
    } else {
        Stop-VM -VMName $VMName -TurnOff -Passthru | Select-Object Name, State
    }
}

function Invoke-RestartVM {
    param([string]$VMName)
    if ($DryRun) {
        Write-Host "[Dry-Run] Restart-VM -VMName $VMName -Force" -ForegroundColor Yellow
        Log-WhatIf -ActionType 'Restart-VM' -Details @{ VMName = $VMName }
        return [pscustomobject]@{ Name = $VMName; State = 'WouldRestart' }
    } else {
        Restart-VM -VMName $VMName -Force -Passthru | Select-Object Name, State
    }
}

function Invoke-QemuConvert {
    param([string]$Source, [string]$Dest)
    if ($DryRun) {
        Write-Host "[Dry-Run] qemu-img convert -f raw -O vhdx `"$Source`" `"$Dest`"" -ForegroundColor Yellow
        Log-WhatIf -ActionType 'qemu-convert' -Details @{ Source = $Source; Dest = $Dest }
        return $true
    }

    if (-not (Test-Path $Source)) {
        Write-Warning "Source not found: $Source"
        return $false
    }

    # Actual qemu-img run (simplified; replace with your robust Start-Process implementation)
    $exe = $script:qemuImgPath
    $args = "convert -f raw -O vhdx `"$Source`" `"$Dest`""

    # Check if qemu-img exists
    if (-not (Get-Command $exe -ErrorAction SilentlyContinue)) {
        Write-Error "qemu-img executable not found. Ensure '$exe' is on PATH or set \$qemuImgPath."
        return $false
    }

    Write-Host "Running: $exe $args" -ForegroundColor White
    try {
        $ErrorFile = [System.IO.Path]::GetTempFileName()
        $p = Start-Process -FilePath $exe -ArgumentList $args -NoNewWindow -Wait -PassThru -RedirectStandardError $ErrorFile -ErrorAction Stop

        if ($p.ExitCode -ne 0) {
            $ErrorOutput = Get-Content $ErrorFile -ErrorAction SilentlyContinue
            Write-Error "qemu-img failed with exit code $($p.ExitCode). Error Output: $($ErrorOutput -join ' ')"
            Remove-Item $ErrorFile -Force -ErrorAction SilentlyContinue
            return $false
        }
        Remove-Item $ErrorFile -Force -ErrorAction SilentlyContinue
        Write-Host "[OK] Converted $Source -> $Dest" -ForegroundColor Green
        return $true
    } catch {
        Write-Error "Failed to run qemu-img: $_"
        return $false
    }
}
#endregion
# ==========================================
#region * Interactive per-VM actions *
# ==========================================
function Show-VMActions {
    param([Parameter(Mandatory=$true)] [array]$VMObjects)

    if (-not $VMObjects -or $VMObjects.Count -eq 0) {
        Write-Host "No router VMs found matching '$VMNamePattern'." -ForegroundColor Yellow
        Read-Host 'Press Enter to continue'
        return
    }

    while ($true) {
        Clear-Host
        # Re-query VMs to ensure up-to-date status in the list view
        $VMObjects = if ($DryRun) { Get-RouterVMs } else { Get-RouterVMs | ForEach-Object { Get-VM -Name $_.Name } }

        Write-Host "Select a VM to manage (or Q to return):" -ForegroundColor Cyan
        for ($i = 0; $i -lt $VMObjects.Count; $i++) {
            $vm = $VMObjects[$i]
            Write-Host (" [{0}] {1} - {2}" -f ($i + 1), $vm.Name, $vm.State)
        }
        Write-Host " [0] Go to What-If/Execute Menu"
        $selection = Read-Host 'Enter VM number, 0, or Q'

        if ($selection -match '^[Qq]$') { break }
        if ($selection -eq '0') { return } # Exit to main menu for What-If

        if ($selection -notmatch '^\d+$' -or [int]$selection -lt 1 -or [int]$selection -gt $VMObjects.Count) {
            Write-Host "Invalid selection, try again." -ForegroundColor Red
            Start-Sleep -Seconds 1
            continue
        }

        $index = [int]$selection - 1
        $selectedVM = $VMObjects[$index]

        while ($true) {
            Clear-Host
            # Refresh live state if not dry-run
            if (-not $DryRun) { $selectedVM = Get-VM -Name $selectedVM.Name }
            Write-Host "VM: $($selectedVM.Name)    State: $($selectedVM.State)" -ForegroundColor Cyan
            Write-Host " [1] Start"
            Write-Host " [2] Stop (TurnOff)"
            Write-Host " [3] Restart (Force)"
            Write-Host " [4] Refresh VM State"
            Write-Host " [Q] Back to VM list"
            $action = Read-Host 'Choose action'

            switch ($action) {
                '1' {
                    if (($selectedVM.State -eq 'Running') -and -not $DryRun) {
                        Write-Host "VM is already running." -ForegroundColor Yellow
                    } else {
                        $confirm = Read-Host "Start VM '$($selectedVM.Name)'? (y/N)"
                        if ($confirm -match '^[Yy]') {
                            Invoke-StartVM -VMName $selectedVM.Name | Format-Table -AutoSize
                        } else {
                            Write-Host "Start canceled." -ForegroundColor DarkGray
                        }
                    }
                    Read-Host 'Press Enter to continue'
                }
                '2' {
                    if (($selectedVM.State -ne 'Running') -and -not $DryRun) {
                        Write-Host "VM is not running." -ForegroundColor Yellow
                    } else {
                        $confirm = Read-Host "Stop (TurnOff) VM '$($selectedVM.Name)'? (y/N)"
                        if ($confirm -match '^[Yy]') {
                            Invoke-StopVM -VMName $selectedVM.Name | Format-Table -AutoSize
                        } else {
                            Write-Host "Stop canceled." -ForegroundColor DarkGray
                        }
                    }
                    Read-Host 'Press Enter to continue'
                }
                '3' {
                    $confirm = Read-Host "Restart VM '$($selectedVM.Name)'? (y/N)"
                    if ($confirm -match '^[Yy]') {
                        Invoke-RestartVM -VMName $selectedVM.Name | Format-Table -AutoSize
                    } else {
                        Write-Host "Restart canceled." -ForegroundColor DarkGray
                    }
                    Read-Host 'Press Enter to continue'
                }
                '4' {
                    if ($DryRun) {
                        Write-Host "[Dry-Run] Refresh skipped (would query Get-VM in real run)." -ForegroundColor Yellow
                    } else {
                        $selectedVM = Get-VM -Name $selectedVM.Name
                        Write-Host "Refreshed: $($selectedVM.Name) - $($selectedVM.State)" -ForegroundColor Green
                    }
                    Read-Host 'Press Enter to continue'
                }
                { $_ -match '^[Qq]$' } { break }
                default {
                    Write-Host "Invalid choice." -ForegroundColor Red
                    Start-Sleep -Seconds 1
                }
            }
        }
    }
}
#endregion
# ==========================================
#region * MenuContext *
# ==========================================
function Build-MenuContext {
    $routerVMs = if ($DryRun) { Get-RouterVMs } else { Get-RouterVMs | ForEach-Object { Get-VM -Name $_.Name } }

    $openwrtImg = Join-Path $VMRoot 'openwrt.img'
    $openwrtVhdx = Join-Path $VMRoot 'openwrt.vhdx'
    $ddwrtImg = Join-Path $VMRoot 'dd-wrt.image'
    $ddwrtVhdx = Join-Path $VMRoot 'dd-wrt.vhdx'
    $statusOpenwrt = Get-ImageStatus -FilePath $openwrtVhdx
    $statusDDWRT = Get-ImageStatus -FilePath $ddwrtVhdx

    return [ordered]@{
        'VM Control' = @{
            Description = 'Start, Stop, or Restart Router VMs';
            Items = {
                @(
                    [PSCustomObject]@{ Key='A'; Name='Start All Router VMs (Queues)'; Action={ Get-RouterVMs | ForEach-Object { Invoke-StartVM -VMName $_.Name } } }
                    [PSCustomObject]@{ Key='O'; Name='Stop All Router VMs (Queues)'; Action={ Get-RouterVMs | ForEach-Object { Invoke-StopVM -VMName $_.Name } } }
                    [PSCustomObject]@{ Key='R'; Name='Restart All Router VMs (Queues)'; Action={ Get-RouterVMs | ForEach-Object { Invoke-RestartVM -VMName $_.Name } } }
                    [PSCustomObject]@{ Key='S'; Name='Manage Individual VM Actions'; Action={
                        $vms = if ($DryRun) { Get-RouterVMs } else { Get-RouterVMs | ForEach-Object { Get-VM -Name $_.Name } }
                        Show-VMActions -VMObjects $vms
                    } }
                )
            }
        }

        'Rebuild Images' = @{
            Description = 'Convert raw router images to VHDX format using qemu-img';
            Items = {
                @(
                    [PSCustomObject]@{
                        Key='1'
                        Name="Rebuild OpenWrt VHDX ($statusOpenwrt) (Queues)"
                        Action={
                            Write-Host 'Queuing OpenWrt image rebuild...' -ForegroundColor Yellow
                            Invoke-QemuConvert -Source $openwrtImg -Dest $openwrtVhdx | Out-Null
                        }
                    }
                    [PSCustomObject]@{
                        Key='2'
                        Name="Rebuild DD-WRT VHDX ($statusDDWRT) (Queues)"
                        Action={
                            Write-Host 'Queuing DD-WRT image rebuild...' -ForegroundColor Yellow
                            Invoke-QemuConvert -Source $ddwrtImg -Dest $ddwrtVhdx | Out-Null
                        }
                    }
                )
            }
        }

        'What-If / Execute Actions' = @{
            Description = 'Review and Execute Pending Changes';
            Items = {
                @(
                    [PSCustomObject]@{ Key='E'; Name="EXECUTE All Queued Actions ({0} pending)" -f $WhatIfQueue.Count; Action={ Confirm-And-Execute-WhatIf } }
                    [PSCustomObject]@{ Key='V'; Name='View Pending What-If Summary'; Action={ Show-WhatIfSummary; Read-Host 'Press Enter to continue' } }
                    [PSCustomObject]@{ Key='L'; Name='View What-If Log File'; Action={ View-WhatIfLog } }
                    [PSCustomObject]@{ Key='C'; Name='Clear What-If Queue and Log'; Action={ Clear-WhatIf; Write-Host 'Queue and log cleared.' -ForegroundColor Green; Read-Host 'Press Enter to continue' } }
                )
            }
        }

        'Switch Info' = @{
            Description = 'Display Hyper-V virtual switch configuration';
            Items = {
                @(
                    [PSCustomObject]@{ Key='L'; Name='List Virtual Switches'; Action={ Get-VMSwitch | Select-Object Name, SwitchType, NetAdapterInterfaceDescription | Format-Table -AutoSize } }
                    [PSCustomObject]@{ Key='A'; Name='Show Attached Network Adapters'; Action={ Get-VMNetworkAdapter | Select-Object VMName, SwitchName, Name, MacAddress | Format-Table -AutoSize } }
                )
            }
        }

        'Diagnostics' = @{
            Description = 'View VM and Hyper-V Diagnostics';
            Items = {
                @(
                    [PSCustomObject]@{ Key='V'; Name='View Router VM States'; Action={
                        Get-RouterVMs | ForEach-Object {
                            if ($DryRun) { [PSCustomObject]@{ Name = $_.Name; State = 'N/A (DryRun)'; Uptime = 'N/A' } }
                            else { Get-VM -Name $_.Name }
                        } | Select-Object Name, State, Uptime | Format-Table -AutoSize
                    } }
                    [PSCustomObject]@{ Key='E'; Name='View Recent Hyper-V Events'; Action={ Get-WinEvent -LogName 'Microsoft-Windows-Hyper-V-VMMS-Admin' -MaxEvents 10 | Select-Object TimeCreated, Id, Message | Format-Table -Wrap -AutoSize } }
                )
            }
        }
    }
}
#endregion
# ==========================================
#region * Menu Loop *
# ==========================================
$cancel = $false
# Register event to catch Ctrl+C or process exit
$null = Register-EngineEvent PowerShell.Exiting -Action { $cancel = $true }

# Auto-refresh loop
try {
    while ($RunUntilCancelled -and -not $cancel) {
        Clear-Host
        $MenuContext = Build-MenuContext

        # Display current dry-run status prominently
        $MenuTitle = "Hyper-V Router Management Menu" + (if ($DryRun) { " [DRY-RUN: Actions MUST BE EXECUTED]" } else { " [LIVE MODE: Actions RUN IMMEDIATELY]" })

        Show-InteractiveMenu -Context $MenuContext -Title $MenuTitle
        Write-Host ""
        Write-Host "Pending Actions: $($WhatIfQueue.Count)" -ForegroundColor (if ($WhatIfQueue.Count -gt 0) { "Red" } else { "DarkGray" })
        Write-Host "Refreshing menu data in $RefreshSeconds seconds (Ctrl+C to exit)..." -ForegroundColor DarkGray
        Start-Sleep -Seconds $RefreshSeconds
    }
} finally {
    Unregister-Event -SourceIdentifier PowerShell.Exiting -ErrorAction SilentlyContinue
    Write-Host "Exiting menu." -ForegroundColor Yellow
}
#endregion
