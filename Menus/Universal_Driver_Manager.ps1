#==========================================#
#region Helper: convert version
#==========================================#
function Convert-ToVersion {
    param([string]$VersionString)
    if (-not $VersionString) { return $null }
    try {
        $clean = ($VersionString -split '\s')[0] -replace '[^0-9\.]',''
        return [version]$clean
    } catch {
        return $null
    }
}
#endregion
#==========================================#
#region Get devices by PnP class or all devices
#==========================================#
function Get-DevicesByClass {
    [CmdletBinding()]
    param(
        [string]$DeviceClass = 'Bluetooth',
        [switch]$PresentOnly
    )
    Write-Verbose "Calling Get-PnpDevice -Class $DeviceClass -PresentOnly:$PresentOnly"
    try {
        if ($DeviceClass -and ($DeviceClass -ne 'All')) {
            if ($PresentOnly) {
                $devices = Get-PnpDevice -Class $DeviceClass -PresentOnly -ErrorAction Stop
            } else {
                $devices = Get-PnpDevice -Class $DeviceClass -ErrorAction Stop
            }
        } else {
            if ($PresentOnly) {
                $devices = Get-PnpDevice -PresentOnly -ErrorAction Stop
            } else {
                $devices = Get-PnpDevice -ErrorAction Stop
            }
        }

        $devices | Select-Object @{Name='FriendlyName';Expression={$_.FriendlyName}},
                                 @{Name='InstanceId';Expression={$_.InstanceId}},
                                 @{Name='Status';Expression={$_.Status}},
                                 @{Name='Class';Expression={$_.Class}},
                                 @{Name='Manufacturer';Expression={$_.Manufacturer}}
    } catch {
        Write-Color "Error: Failed to enumerate devices for class '$DeviceClass' - $_" -Foreground Red
        return @()
    }
}
#endregion
#==========================================#
#region Get installed driver info
#==========================================#
function Get-DeviceDriverInfo {
    [CmdletBinding()]
    param(
        [string]$InstanceId
    )
    Write-Verbose "Querying Win32_PnPSignedDriver"
    $drivers = Get-CimInstance -ClassName Win32_PnPSignedDriver -ErrorAction SilentlyContinue
    if (-not $drivers) { return @() }

    if ($InstanceId) {
        $match = $drivers | Where-Object {
            ($_.DeviceID -eq $InstanceId) -or ($_.DeviceID -like "*$InstanceId*") -or ($_.DeviceName -like "*$InstanceId*")
        }
    } else {
        $match = $drivers
    }

    $match | Select-Object DeviceName, DeviceID, Manufacturer, DriverVersion, @{Name='DriverVersionParsed';Expression={ Convert-ToVersion $_.DriverVersion }}, InfName, @{Name='DriverDate';Expression={ if ($_.DriverDate) { [datetime]::ParseExact($_.DriverDate.Substring(0,8),'yyyyMMdd',[System.Globalization.CultureInfo]::InvariantCulture) } else { $null } }}
}
#endregion
#==========================================#
#region Query Windows Update for driver updates
#==========================================#
function Get-AvailableDriverUpdates {
    [CmdletBinding()]
    param()
    Write-Verbose "Querying Windows Update Agent for driver updates"
    try {
        $session = New-Object -ComObject Microsoft.Update.Session
        $searcher = $session.CreateUpdateSearcher()
        $result = $searcher.Search("IsInstalled=0 and Type='Driver'")
        $updates = @()
        $i = 0
        foreach ($u in $result.Updates) {
            $i++
            Show-StatusBar -Message "Collecting Windows Update driver list ($i of $($result.Updates.Count))" -Percent ([Math]::Round(($i / $result.Updates.Count) * 100)) -Level Info
            $updates += [PSCustomObject]@{
                Title = $u.Title
                Description = $u.Description
                KBArticleIDs = ($u.KBArticleIDs -join ',')
                Categories = ($u.Categories | ForEach-Object { $_.Name } -join ',')
                Identity = $u.Identity.UpdateID
                RebootRequired = $u.RebootRequired
            }
        }
        Show-StatusBar -Message "Windows Update driver list collected" -Percent 100 -Level Success
        return $updates
    } catch {
        Show-StatusBar -Message "Failed to query Windows Update" -Level Error
        Write-Color "Error: Failed to query Windows Update for driver updates - $_" -Foreground Red
        return @()
    }
}
#endregion
#==========================================#
#region Compare drivers
#==========================================#
function Compare-Drivers {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][array]$Devices,
        [Parameter(Mandatory=$true)][array]$InstalledDrivers,
        [Parameter(Mandatory=$true)][array]$AvailableDriverUpdates
    )

    Write-Verbose "Comparing installed drivers to available updates"
    $count = $Devices.Count
    $idx = 0
    $report = foreach ($dev in $Devices) {
        $idx++
        $pct = if ($count -gt 0) { [Math]::Round(($idx / $count) * 100) } else { -1 }
        Show-StatusBar -Message "Comparing device $idx of $count: $($dev.FriendlyName)" -Percent $pct -Level Info

        $installed = $InstalledDrivers | Where-Object {
            ($_.DeviceID -like "*$($dev.InstanceId)*") -or ($_.DeviceName -like "*$($dev.FriendlyName)*") -or ($_.DeviceName -like "*$($dev.Class)*")
        } | Select-Object -First 1

        $searchTerms = @()
        if ($dev.FriendlyName) { $searchTerms += ($dev.FriendlyName -replace '\W','') }
        if ($installed -and $installed.DeviceName) { $searchTerms += ($installed.DeviceName -replace '\W','') }
        if ($dev.Manufacturer) { $searchTerms += ($dev.Manufacturer -replace '\W','') }

        $possibleUpdates = @()
        foreach ($t in $searchTerms | Where-Object { $_ }) {
            $possibleUpdates += $AvailableDriverUpdates | Where-Object { $_.Title -and ($_.Title -match [regex]::Escape($t)) }
        }
        $possibleUpdates = $possibleUpdates | Select-Object -Unique

        $installedVersion = if ($installed) { Convert-ToVersion $installed.DriverVersion } else { $null }
        $newerUpdateFound = $false
        if ($installedVersion -and $possibleUpdates) {
            $newerUpdateFound = $true
        }

        [PSCustomObject]@{
            FriendlyName       = $dev.FriendlyName
            InstanceId         = $dev.InstanceId
            Class              = $dev.Class
            Status             = $dev.Status
            DriverInstalled    = if ($installed) { $true } else { $false }
            InstalledDriver    = if ($installed) { $installed.DeviceName } else { $null }
            InstalledVersion   = if ($installed) { $installed.DriverVersion } else { $null }
            InstalledVersionParsed = if ($installed) { $installed.DriverVersionParsed } else { $null }
            Manufacturer       = if ($installed) { $installed.Manufacturer } else { $dev.Manufacturer }
            DriverDate         = if ($installed) { $installed.DriverDate } else { $null }
            AvailableUpdates   = if ($possibleUpdates) { ($possibleUpdates | ForEach-Object { $_.Title }) -join '; ' } else { $null }
            UpdateCandidates   = if ($possibleUpdates) { ($possibleUpdates | ForEach-Object { $_.Identity }) -join '; ' } else { $null }
            NewerUpdateFound   = $newerUpdateFound
        }
    }

    Show-StatusBar -Message "Comparison complete" -Percent 100 -Level Success
    return $report
}
#endregion
#==========================================#
#region Export CSV
#==========================================#
function Export-DriverReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][array]$Report,
        [Parameter(Mandatory=$false)][string]$Path = ".\UniversalDriverReport.csv",
        [switch]$Force,
        [switch]$DryRun
    )
    Write-Verbose "Preparing to export CSV to $Path (DryRun=$DryRun)"
    if ($DryRun) {
        Show-StatusBar -Message "DryRun: would export $($Report.Count) rows to $Path" -Level Warn
        Write-Color "DryRun: would export $($Report.Count) rows to $Path" -Foreground Yellow
        return
    }

    try {
        if ((Test-Path $Path) -and (-not $Force)) {
            throw "File exists. Use -Force to overwrite."
        }
        $Report | Export-Csv -Path $Path -NoTypeInformation -Encoding UTF8
        Show-StatusBar -Message "Exported report to $Path" -Level Success
        Write-Color "Exported report to $Path" -Foreground Green
    } catch {
        Show-StatusBar -Message "Failed to export CSV" -Level Error
        Write-Color "Error: Failed to export CSV - $_" -Foreground Red
    }
}
#endregion
#==========================================#
#region Orchestrator
#==========================================#
function Get-UniversalDriverInventory {
    [CmdletBinding()]
    param(
        [string]$DeviceClass = 'Bluetooth',
        [switch]$PresentOnly,
        [switch]$IncludeWindowsUpdateChecks,
        [switch]$DryRun,
        [switch]$Verbose
    )

    Show-Header -Title "Universal Driver Inventory" -DryRun:$DryRun -Verbose:$Verbose
    Show-StatusBar -Message "Starting scan for class: $DeviceClass" -Level Info

    $devices = Get-DevicesByClass -DeviceClass $DeviceClass -PresentOnly:$PresentOnly
    Show-StatusBar -Message "Found $($devices.Count) device(s) for class '$DeviceClass'" -Level Info -Percent 5

    $installedDrivers = Get-DeviceDriverInfo

    $availableUpdates = @()
    if ($IncludeWindowsUpdateChecks) {
        if ($DryRun) {
            Show-StatusBar -Message "DryRun: skipping Windows Update query" -Level Warn
        } else {
            Show-StatusBar -Message "Querying Windows Update for driver packages..." -Level Info
            $availableUpdates = Get-AvailableDriverUpdates
        }
    }

    Show-StatusBar -Message "Comparing drivers..." -Level Info -Percent 50
    $report = Compare-Drivers -Devices $devices -InstalledDrivers $installedDrivers -AvailableDriverUpdates $availableUpdates

    Show-StatusBar -Message "Inventory complete" -Level Success -Percent 100
    Write-Host ''
    return [PSCustomObject]@{
        Timestamp = (Get-Date)
        DeviceClass = $DeviceClass
        PresentOnly = $PresentOnly
        Devices = $devices
        InstalledDrivers = $installedDrivers
        AvailableDriverUpdates = $availableUpdates
        InventoryReport = $report
    }
}
#endregion
#==========================================#
#region Simple placeholder for install (respects DryRun)
#==========================================#
function Install-DriverCandidate {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory=$true)][string]$UpdateIdentity,
        [switch]$DryRun
    )
    if ($DryRun) {
        Show-StatusBar -Message "DryRun: would install update $UpdateIdentity" -Level Warn
        Write-Color "DryRun: would install update $UpdateIdentity" -Foreground Yellow
        return $true
    }

    Show-StatusBar -Message "Install not implemented" -Level Warn
    Write-Color "Install-DriverCandidate: automatic install not implemented in this script." -Foreground Yellow
    return $false
}
#endregion
#==========================================#
#region Drivers menu options (user-provided)
#==========================================#
$driversMenuOptions = @(
    [PSCustomObject]@{ Id='1'; Name='Scan devices by class'; Description=''; Action={
        $class = Read-Host "Enter PnP class name (e.g., Bluetooth, Net, USB, Disk). Use 'All' for all classes"
        $presentOnly = Read-Host "Present only? (Y/N)"
        $presentSwitch = $false
        if ($presentOnly -match '^[Yy]') { $presentSwitch = $true }
        $global:LastResult = Get-UniversalDriverInventory -DeviceClass $class -PresentOnly:$presentSwitch -IncludeWindowsUpdateChecks:$false -DryRun:$DryRun -Verbose:$Verbose
        Write-Color "Scan complete. Found $($global:LastResult.InventoryReport.Count) items." -Foreground Green
        Pause } }
    [PSCustomObject]@{ Id='2'; Name='Scan all present devices'; Description=''; Action={
        $global:LastResult = Get-UniversalDriverInventory -DeviceClass 'All' -PresentOnly -IncludeWindowsUpdateChecks:$false -DryRun:$DryRun -Verbose:$Verbose
        Write-Color "Scan complete. Found $($global:LastResult.InventoryReport.Count) items." -Foreground Green
        Pause } }
    [PSCustomObject]@{ Id='3'; Name='Scan and check Windows Update for driver packages'; Description=''; Action={
        $class = Read-Host "Enter PnP class name (or 'All')"
        $presentOnly = Read-Host "Present only? (Y/N)"
        $presentSwitch = $false
        if ($presentOnly -match '^[Yy]') { $presentSwitch = $true }
        $global:LastResult = Get-UniversalDriverInventory -DeviceClass $class -PresentOnly:$presentSwitch -IncludeWindowsUpdateChecks -DryRun:$DryRun -Verbose:$Verbose
        Write-Color "Scan + Windows Update check complete. Found $($global:LastResult.InventoryReport.Count) items." -Foreground Green
        Pause } }
    [PSCustomObject]@{ Id='4'; Name='Export last report to CSV'; Description=''; Action={
        if (-not $global:LastResult) {
            Write-Color "No report available. Run option 1, 2, or 3 first." -Foreground Yellow
            Pause
            return
        }
        $path = Read-Host "Enter CSV path (default .\UniversalDriverReport.csv)"
        if (-not $path) { $path = ".\UniversalDriverReport.csv" }
        Export-DriverReport -Report $global:LastResult.InventoryReport -Path $path -Force -DryRun:$DryRun
        Pause } }
    [PSCustomObject]@{ Id='5'; Name='Show last report (table)'; Description=''; Action={
        if (-not $global:LastResult) {
            Write-Color "No report available. Run option 1, 2, or 3 first." -Foreground Yellow
        } else {
            $global:LastResult.InventoryReport | Format-Table -AutoSize
        }
        Pause } }
    [PSCustomObject]@{ Id='q'; Name='Exit'; Description=''; Action={
        Write-Color "Exiting menu." -Foreground Yellow
        # signal to caller to exit by setting a flag
        $script:MenuExitRequested = $true } }
)
#endregion
#==========================================#
#region Generic menu renderer that uses $driversMenuOptions
#==========================================#
function Show-DriversMenu {
    [CmdletBinding()]
    param(
        [switch]$DryRun,
        [switch]$Verbose
    )

    # Ensure menu exit flag is reset
    $script:MenuExitRequested = $false

    while (-not $script:MenuExitRequested) {
        Show-Header -Title "Universal Driver Inventory" -DryRun:$DryRun -Verbose:$Verbose

        # Print menu entries with colors and descriptions
        foreach ($opt in $driversMenuOptions) {
            $id = $opt.Id
            $name = $opt.Name
            Write-Color ("[{0}] {1}" -f $id, $name) -Foreground Cyan
            if ($opt.Description) {
                Write-Color ("    {0}" -f $opt.Description) -Foreground DarkGray
            }
        }

        $choice = Read-Host "Choose an option (enter Id, e.g., 1 or q)"

        # Find matching option by Id (case-insensitive)
        $selected = $driversMenuOptions | Where-Object { $_.Id -ieq $choice } | Select-Object -First 1

        if (-not $selected) {
            Write-Color "Invalid selection: $choice" -Foreground Red
            Pause
            continue
        }

        try {
            # Show status and run the action scriptblock
            Show-StatusBar -Message "Executing: $($selected.Name)" -Level Info -Percent 0
            & $selected.Action
            Show-StatusBar -Message "Completed: $($selected.Name)" -Level Success -Percent 100
        } catch {
            Show-StatusBar -Message "Error executing action: $($_.Exception.Message)" -Level Error
            Write-Color "Error: $($_.Exception.Message)" -Foreground Red
        }
    }
}
#endregion
#==========================================#
# Replace previous menu call with:
#==========================================#
# Show-DriversMenu -DryRun:$DryRun -Verbose:$Verbose
