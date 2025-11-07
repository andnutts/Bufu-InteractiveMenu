# ==================================================================
# Filename: Link_Rclone-Manager.ps1
# Description: Main script for the PC Maintenance and Utility Menu,
# which relies on the InteractiveMenu.psm1 module.
# ==================================================================
<#
.SYNOPSIS
    An interactive PowerShell script to create and manage directory symbolic links,
    junctions, and perform common Rclone operations.
.DESCRIPTION
    This script provides a menu-driven interface for:
    1. Creating Directory Symbolic Links (Requires Admin)
    2. Creating Directory Junctions
    3. Removing Links/Junctions
    4. Managing common Rclone tasks (List remotes, Sync, Copy)
#>
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
#region * Helper Functions *
# ==================================================================
function Test-IsAdmin {
    $currentUser = New-Object Security.Principal.WindowsPrincipal ([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Pause-Script {
    Write-Host ""
    Read-Host -Prompt "Press Enter to return to the menu..." | Out-Null
}

function Check-Rclone {
    if (-not (Get-Command rclone -ErrorAction SilentlyContinue)) {
        Write-Warning "Rclone not found. Please ensure 'rclone.exe' is installed and in your system's PATH."
        return $false
    }
    return $true
}

# ==================================================================
# --- Link Management Functions ---
# ==================================================================
function New-Symlink {
    Write-Host "--- Create Directory Symbolic Link ---" -ForegroundColor Yellow
    if (-not (Test-IsAdmin)) {
        Write-Warning "Creating symbolic links requires running PowerShell as an Administrator."
        Write-Warning "Please re-run this script with 'Run as Administrator'."
        return
    }

    $linkPath = Read-Host "Enter the path for the NEW link (e.g., C:\MyLink)"
    $targetPath = Read-Host "Enter the path for the TARGET directory (e.g., D:\MyData)"

    if (-not (Test-Path $targetPath -PathType Container)) {
        Write-Error "Target directory '$targetPath' does not exist."
        return
    }
    if (Test-Path $linkPath) {
        Write-Error "A file or folder already exists at '$linkPath'."
        return
    }

    try {
        New-Item -Path $linkPath -ItemType SymbolicLink -Value $targetPath -ErrorAction Stop
        Write-Host "Success! Symbolic link created." -ForegroundColor Green
        Write-Host "$linkPath -> $targetPath"
    }
    catch {
        Write-Error "Failed to create symbolic link. Error: $($_.Exception.Message)"
    }
}

function New-Junction {
    Write-Host "--- Create Directory Junction ---" -ForegroundColor Yellow
    Write-Host "Junctions are for local directories only and do not require admin rights."

    $linkPath = Read-Host "Enter the path for the NEW junction (e.g., C:\MyJunction)"
    $targetPath = Read-Host "Enter the path for the TARGET directory (e.g., D:\MyData)"

    if (-not (Test-Path $targetPath -PathType Container)) {
        Write-Error "Target directory '$targetPath' does not exist."
        return
    }
    if (Test-Path $linkPath) {
        Write-Error "A file or folder already exists at '$linkPath'."
        return
    }

    try {
        # Note: Junction creation uses 'Target' parameter for directory target, not 'Value'
        # The New-Item -ItemType Junction automatically uses 'Value' as 'Target'
        New-Item -Path $linkPath -ItemType Junction -Value $targetPath -ErrorAction Stop
        Write-Host "Success! Junction created." -ForegroundColor Green
        Write-Host "$linkPath => $targetPath"
    }
    catch {
        Write-Error "Failed to create junction. Error: $($_.Exception.Message)"
    }
}

function Remove-Link {
    Write-Host "--- Remove Link or Junction ---" -ForegroundColor Yellow
    $linkPath = Read-Host "Enter the path of the link/junction to remove"

    if (-not (Test-Path $linkPath)) {
        Write-Error "Path '$linkPath' does not exist."
        return
    }

    # Check if it's a link (ReparsePoint is the attribute for both)
    $item = Get-Item -Path $linkPath -Force
    if ($item.Attributes.ToString() -notlike "*ReparsePoint*") {
        Write-Error "Path '$linkPath' is not a symbolic link or junction. Aborting for safety."
        return
    }

    $confirmation = Read-Host "Are you sure you want to delete this link (y/n)? This will NOT delete the target data."
    if ($confirmation -ne 'y') {
        Write-Host "Operation cancelled."
        return
    }

    try {
        Remove-Item -Path $linkPath -Force -ErrorAction Stop
        Write-Host "Success! Link '$linkPath' has been removed." -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to remove link. Error: $($_.Exception.Message)"
    }
}

# ==================================================================
# --- Rclone Functions ---
# ==================================================================

function Show-RcloneRemotes {
    Write-Host "--- Rclone: List Remotes ---" -ForegroundColor Cyan
    if (-not (Check-Rclone)) { return }

    Write-Host "Fetching remotes..."
    rclone listremotes
}

function Start-RcloneSync {
    Write-Host "--- Rclone: Sync Directory ---" -ForegroundColor Cyan
    Write-Warning "This makes the destination match the source, DELETING extra files at the destination."
    if (-not (Check-Rclone)) { return }

    $source = Read-Host "Enter the SOURCE path (e.g., C:\MyData or MyRemote:Bucket)"
    $destination = Read-Host "Enter the DESTINATION path (e.g., MyRemote:Backup or C:\Backup)"

    if ([string]::IsNullOrWhiteSpace($source) -or [string]::IsNullOrWhiteSpace($destination)) {
        Write-Error "Source and Destination cannot be empty."
        return
    }

    $cmd = "rclone sync `"$source`" `"$destination`" --progress --interactive"
    Write-Host ""
    Write-Host "Command to be executed:" -ForegroundColor Yellow
    Write-Host $cmd
    Write-Host ""

    $confirmation = Read-Host "Are you sure you want to run this SYNC operation? (y/n)"
    if ($confirmation -eq 'y') {
        Write-Host "Starting sync..."
        # Use Invoke-Expression to handle the command string with quotes correctly
        Invoke-Expression -Command $cmd
        Write-Host "Sync complete." -ForegroundColor Green
    } else {
        Write-Host "Sync cancelled."
    }
}

function Start-RcloneCopy {
    Write-Host "--- Rclone: Copy Directory ---" -ForegroundColor Cyan
    Write-Host "This copies files from source to destination, overwriting existing files but NOT deleting extras."
    if (-not (Check-Rclone)) { return }

    $source = Read-Host "Enter the SOURCE path (e.g., C:\MyData or MyRemote:Bucket)"
    $destination = Read-Host "Enter the DESTINATION path (e.g., MyRemote:Backup or C:\Backup)"

    if ([string]::IsNullOrWhiteSpace($source) -or [string]::IsNullOrWhiteSpace($destination)) {
        Write-Error "Source and Destination cannot be empty."
        return
    }

    $cmd = "rclone copy `"$source`" `"$destination`" --progress --interactive"
    Write-Host ""
    Write-Host "Command to be executed:" -ForegroundColor Yellow
    Write-Host $cmd
    Write-Host ""

    $confirmation = Read-Host "Are you sure you want to run this COPY operation? (y/n)"
    if ($confirmation -eq 'y') {
        Write-Host "Starting copy..."
        Invoke-Expression -Command $cmd
        Write-Host "Copy complete." -ForegroundColor Green
    } else {
        Write-Host "Copy cancelled."
    }
}

# ==================================================================
#region * Define Menu Items *
# ==================================================================

# Determine Admin Status for conditional menu item enablement
$isAdmin = Test-IsAdmin

$MenuTitleExplicit = "Interactive Link & Rclone Manager"

# The menu items are defined here, wrapping the functions and Pause-Script
# The InteractiveMenu module will handle the main loop and display.
$MenuItems = @(
    [PSCustomObject]@{ Id = '1'; Name = 'Create Symbolic Link (Directory) (Admin Required)'; Enabled = $isAdmin
                        Key = '1'
                        Help = 'Creates a directory symbolic link, requiring administrator privileges.'
                        Type = 'Link Management'
                        Action = { New-Symlink; Pause-Script } }
    [PSCustomObject]@{ Id = '2'; Name = 'Create Directory Junction'; Enabled = $true
                        Key = '2'
                        Help = 'Creates a directory junction (local only, no Admin required).'
                        Type = 'Link Management'
                        Action = { New-Junction; Pause-Script } }
    [PSCustomObject]@{ Id = '3'; Name = 'Remove a Link or Junction'; Enabled = $true
                        Key = '3'
                        Help = 'Removes an existing link or junction, leaving the target data intact.'
                        Type = 'Link Management'
                        Action = { Remove-Link; Pause-Script } }
    [PSCustomObject]@{ Id = '4'; Name = 'Rclone: List Remotes'; Enabled = $true
                        Key = '4'
                        Help = 'Lists all configured Rclone remotes (e.g., S3, Google Drive, OneDrive).'
                        Type = 'Rclone Management'
                        Action = { Show-RcloneRemotes; Pause-Script } }
    [PSCustomObject]@{ Id = '5'; Name = 'Rclone: Sync Directory (Dest matches Source)'; Enabled = $true
                        Key = '5'
                        Help = 'Synchronizes Source to Destination, deleting extraneous files at Destination.'
                        Type = 'Rclone Management'
                        Action = { Start-RcloneSync; Pause-Script } }
    [PSCustomObject]@{ Id = '6'; Name = 'Rclone: Copy Directory (Source -> Dest)'; Enabled = $true
                        Key = '6'
                        Help = 'Copies files from Source to Destination (Safe, does not delete files).'
                        Type = 'Rclone Management'
                        Action = { Start-RcloneCopy; Pause-Script } }
    [PSCustomObject]@{ Id = 'Q'; Name = 'Quit Menu'; Enabled = $true
                        Key = 'Q'
                        Help = 'Exit menu'
                        Type = 'Meta'
                        Action = { return 'quit' } }
)

# Clean up the original custom menu block that is no longer needed
Remove-Variable choice, isAdmin, adminStatus, linkManagemenuActions, rclonemenuActions, allActions -ErrorAction SilentlyContinue

#endregion
# ==================================================================
#region * Run Menu *
# ==================================================================

if (-not [string]::IsNullOrWhiteSpace($MenuTitleExplicit)) {
    $FinalMenuTitle = $MenuTitleExplicit
} else {
    $FinalMenuTitle = Get-MenuTitle
    Write-Verbose "No explicit menu title defined. Falling back to title derived from Get-MenuTitle: '$FinalMenuTitle'."
}

if (Get-Command -Name Show-InteractiveMenu -ErrorAction SilentlyContinue) {
    # The InteractiveMenu module handles the main loop, display, and input based on $MenuItems
    Show-InteractiveMenu -MenuData $MenuItems -MenuTitle $FinalMenuTitle
} else {
    Write-Error "The Show-InteractiveMenu function was not loaded from InteractiveMenu.psm1. Cannot run menu."
}
#endregion
