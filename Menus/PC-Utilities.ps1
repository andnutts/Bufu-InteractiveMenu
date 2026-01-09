# ==================================================================
# Filename: PC-Utilities.ps1
# Description: Main script for the PC Maintenance and Utility Menu,
# which relies on the InteractiveMenu.psm1 module.
# ==================================================================
#region * Import Interactive Menu Module *
# ==================================================================
# Set the path to the InteractiveMenu.psm1 module located in the parent directory
$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
# Assume the module is one level up relative to the Menus folder
$MenuModule = Join-Path (Split-Path $ScriptPath -Parent) 'InteractiveMenu.psm1'

if (Test-Path $MenuModule) {
    . $MenuModule
    Write-Host "[OK] InteractiveMenu.psm1 module loaded." -ForegroundColor Green
} else {
    Write-Error "InteractiveMenu.psm1 not found at '$MenuModule'. Exiting."
    return
}
#endregion
# ==================================================================
#region * Core Functions *
# ==================================================================
function Shutdown-5Min {
    # Shuts down the PC in 5 minutes (300 seconds) with a message
    Write-Host "Scheduling system shutdown in 5 minutes..." -ForegroundColor Yellow
    shutdown /s /t 300 /c "Your PC will shut down in 5 minutes."
}

function Cancel-Shutdown {
    # Aborts any pending system shutdown
    shutdown /a
    Write-Host "Pending shutdown canceled." -ForegroundColor Green
    Pause
}

function Empty-RecycleBin {
    # Clears the recycle bin for all drives
    Write-Host "Emptying Recycle Bin..." -ForegroundColor Yellow
    Clear-RecycleBin -Force
    Write-Host "Recycle Bin emptied." -ForegroundColor Green
    Pause
}

function Clear-TempFile {
    # Deletes contents of the current user's temporary directory
    Write-Host "Clearing temporary files..." -ForegroundColor Yellow
    Remove-Item "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "Temporary files cleared." -ForegroundColor Green
    Pause
}

function Show-SystemInfo {
    # Displays selected system hardware and OS information
    Write-Host "--- System Information ---" -ForegroundColor Cyan
    Get-ComputerInfo | Select-Object CsName, WindowsVersion, OsArchitecture, CsProcessors, CsTotalPhysicalMemory | Format-List
    Write-Host "--------------------------" -ForegroundColor Cyan
    Pause
}

function List-Program {
    # Lists installed applications from the registry
    Write-Host "--- Installed Programs (may take a moment) ---" -ForegroundColor Cyan
    Get-ItemProperty HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* |
    Select-Object DisplayName, DisplayVersion, Publisher |
    Sort-Object DisplayName |
    Format-Table -AutoSize -Wrap
    Write-Host "---------------------------------------------" -ForegroundColor Cyan
    Pause
}

function Test-Speed {
    # Runs an internet speed test using the SpeedtestCLI module
    Write-Host "Attempting to run Internet Speedtest..." -ForegroundColor Yellow
    try {
        # Check if module exists, install if not (user scope to avoid admin rights issue)
        if (-not (Get-Module -ListAvailable -Name SpeedtestCLI)) {
            Write-Host "Installing SpeedtestCLI module..." -ForegroundColor Yellow
            Install-Module -Name SpeedtestCLI -Force -Scope CurrentUser -ErrorAction Stop
        }
        Import-Module SpeedtestCLI
        Speedtest
    } catch {
        Write-Host "ERROR: Failed to run speed test. Make sure you can install modules." -ForegroundColor Red
    }
    Pause
}

function Get-PublicIP {
    # Fetches the public IP address from a simple external API
    Write-Host "Fetching Public IP..." -ForegroundColor Yellow
    try {
        $ip = Invoke-RestMethod -Uri "https://api.ipify.org?format=json"
        Write-Host "Your Public IP Address is: $($ip.ip)" -ForegroundColor Green
    } catch {
        Write-Host "Could not retrieve IP address. Check network connection." -ForegroundColor Red
    }
    Pause
}

function Pomodoro-Timer {
    # Starts a simple 25-minute Pomodoro timer
    $minutes = 25
    Write-Host "Starting 25-minute Pomodoro Timer. Press any key to stop." -ForegroundColor Yellow
    for ($i = $minutes; $i -gt 0; $i--) {
        Write-Host "$i minute(s) remaining..." -ForegroundColor Cyan
        # Check if user pressed a key every second
        for ($j = 0; $j -lt 60; $j++) {
            if ([Console]::KeyAvailable) {
                $null = [Console]::ReadKey($true)
                Write-Host "Timer stopped by user." -ForegroundColor Red
                Pause
                return
            }
            Start-Sleep -Seconds 1
        }
    }
    [console]::beep(1000,500)
    Write-Host "Pomodoro complete! Take a break." -ForegroundColor Magenta
    Pause
}

function Quote-Of-The-Day {
    # Fetches a random quote from the Quotable API
    Write-Host "Fetching Quote of the Day..." -ForegroundColor Yellow
    try {
        $quote = Invoke-RestMethod -Uri "https://api.quotable.io/random"
        Write-Host ""
        Write-Host "`"$($quote.content)`"" -ForegroundColor Green
        Write-Host "— $($quote.author)" -ForegroundColor Cyan
    } catch {
        Write-Host "Could not fetch quote. Check API status or network connection." -ForegroundColor Red
    }
    Pause
}
#endregion
# ==================================================================
#region * Define Menu Items *
# ==================================================================
$MenuItems = @(
    [PSCustomObject]@{  Id      = '1'; Name = '5 Minute Shutdown';              Enabled = $true
                        Key     = 's'
                        Help    = 'Initiates a 5-minute system shutdown.'
                        Type    = 'Action'
                        Action  = { Shutdown-5Min } }
    [PSCustomObject]@{  Id      = '2'; Name = 'Cancel Shutdown';                Enabled = $true
                        Key     = 'c'
                        Help    = 'Cancels any pending system shutdown.'
                        Type    = 'Action'
                        Action  = { Cancel-Shutdown } }
    [PSCustomObject]@{  Id      = '3'; Name = 'Empty Recycle Bin';              Enabled = $true
                        Key     = 'r'
                        Help    = 'Permanently deletes all files in the Recycle Bin.'
                        Type    = 'Action'
                        Action  = { Empty-RecycleBin } }
    [PSCustomObject]@{  Id      = '4'; Name = 'Clear Temporary Files';          Enabled = $true
                        Key     = 't'
                        Help    = 'Deletes files from the system temporary directory.'
                        Type    = 'Action'
                        Action  = { Clear-TempFile } }
    [PSCustomObject]@{  Id      = '5'; Name = 'Show System Info';               Enabled = $true
                        Key     = 'i'
                        Help    = 'Displays basic system and OS information.'
                        Type    = 'Action'
                        Action  = { Show-SystemInfo } }
    [PSCustomObject]@{  Id      = '6'; Name = 'List Installed Programs';        Enabled = $true
                        Key     = 'l'
                        Help    = 'Lists programs installed on the system.'
                        Type    = 'Action'
                        Action  = { List-Program } }
    [PSCustomObject]@{  Id      = '7'; Name = 'Test Internet Speed';            Enabled = $true
                        Key     = 'p'
                        Help    = 'Runs a speed test (requires SpeedtestCLI module).'
                        Type    = 'Action'
                        Action  = { Test-Speed } }
    [PSCustomObject]@{  Id      = '8'; Name = 'Get Public IP';                  Enabled = $true
                        Key     = 'g'
                        Help    = 'Retrieves and displays the public IP address.'
                        Type    = 'Action'
                        Action  = { Get-PublicIP } }
    [PSCustomObject]@{  Id      = '9'; Name = 'Start Pomodoro Timer (25m)';     Enabled = $true
                        Key     = 'm'
                        Help    = 'Starts a 25-minute Pomodoro focus timer.'
                        Type    = 'Action'
                        Action  = { Pomodoro-Timer } }
    [PSCustomObject]@{  Id      = '10'; Name = 'Quote of the Day';              Enabled = $true
                        Key     = 'q'
                        Help    = 'Fetches a random quote from an online API.'
                        Type    = 'Action'
                        Action  = { Quote-Of-The-Day } }
    [PSCustomObject]@{  Id      = '0'; Name = 'Exit';                           Enabled = $true
                        Key     = 'x'
                        Help    = 'Exits the script.'
                        Type    = 'Exit'
                        Action  = { Write-Host "Exiting script." } }
)
#endregion
# ==================================================================
#region * Run Menu *
# ==================================================================
# Check if the required function from the module is available before running
if (Get-Command -Name Show-InteractiveMenu -ErrorAction SilentlyContinue) {
    Show-InteractiveMenu -MenuData $MenuItems -MenuTitle "PC Maintenance and Utility Menu"
} else {
    Write-Error "The Show-InteractiveMenu function was not loaded from InteractiveMenu.psm1. Cannot run menu."
}
#endregion
