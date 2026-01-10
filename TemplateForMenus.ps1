# Menus Template
# ==================================================================
# Filename:
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
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

# --- PARAMETER GATHERING ---

Write-Host "--- Virtual Router Setup on Hyper-V ---" -ForegroundColor Yellow

# 1. Router Type Selection
$RouterType = Read-Host "Enter Router Type (OpenWRT or DD-WRT): "
if ($RouterType -notlike "OpenWRT" -and $RouterType -notlike "DD-WRT") {
    Write-Error "Invalid router type selected. Exiting."
    Exit
}

# 2. VM Name and Paths
$VMName = Read-Host "Enter the name for your Virtual Machine (e.g., OpenWRT-RTR): "
$VMPath = Read-Host "Enter the root path for VM files (e.g., C:\VMs): "
$VHDXPath = Join-Path -Path $VMPath -ChildPath "$VMName\$VMName.vhdx"
$ImageFile = Read-Host "Enter the full path to the combined router image file (e.g., C:\Downloads\$($RouterType)-image.img): "

# 3. Virtual Switch Configuration (WAN and LAN)
Write-Host "Please ensure you have created a Hyper-V Virtual Switch for your external/WAN and internal/LAN networks." -ForegroundColor Cyan
$WANSwitch = Read-Host "Enter the name of your WAN Hyper-V Virtual Switch: "
$LANSwitch = Read-Host "Enter the name of your LAN Hyper-V Virtual Switch: "

# --- HYPER-V VM CREATION ---

## 1. Create VM Storage Directory and VHDX
Write-Host "`n-- 1. Creating VM Directory and VHDX --" -ForegroundColor Green
$VMDirectory = New-Item -Path $VMPath -Name $VMName -ItemType Directory -Force
$VHDSizeBytes = 5GB # Router OSes are small, but giving room for logs/packages.

try {
    New-VHD -Path $VHDXPath -SizeBytes $VHDSizeBytes -Dynamic
    Write-Host "Successfully created VHDX at: $VHDXPath" -ForegroundColor Green
}
catch {
    Write-Error "Failed to create VHDX. Check the path and permissions."
    Exit
}

## 2. Create the Virtual Machine
Write-Host "`n-- 2. Creating the Virtual Machine --" -ForegroundColor Green

try {
    # Create a Generation 1 VM for best compatibility with router images
    $NewVM = New-VM -Name $VMName `
        -Generation 1 `
        -MemoryStartupBytes 512MB `
        -Path $VMDirectory.FullName `
        -SwitchName $LANSwitch `
        -NoVHD

    # Attach the VHDX
    Add-VMHardDiskDrive -VMName $VMName -Path $VHDXPath

    Write-Host "Successfully created VM '$VMName'." -ForegroundColor Green
}
catch {
    Write-Error "Failed to create VM or attach VHDX. Check SwitchName/Memory/Path."
    Exit
}

# --- CRITICAL MANUAL STEP ---
Write-Host "`n#########################################################################" -ForegroundColor Red
Write-Host "### CRITICAL STEP: WRITE ROUTER IMAGE TO VHDX ###" -ForegroundColor Red
Write-Host "The script will now pause. You must manually write the '$($RouterType)' image" -ForegroundColor Red
Write-Host "file to the created VHDX file before proceeding." -ForegroundColor Red
Write-Host "1. Use a tool (e.g., physdiskwrite.exe, qemu-img) on your host or a helper VM." -ForegroundColor Red
Write-Host "   Target VHDX: $VHDXPath" -ForegroundColor Red
Write-Host "2. Once complete, press [Enter] to continue the PowerShell script." -ForegroundColor Red
Write-Host "#########################################################################" -ForegroundColor Red
Pause

# --- NETWORK CONFIGURATION ---

## 4. Add Second Network Adapter (WAN)
Write-Host "`n-- 4. Configuring Network Adapters --" -ForegroundColor Green
try {
    # Remove the temporary LAN adapter added during New-VM, if it was automatically attached
    # Get-VMNetworkAdapter -VMName $VMName | Where-Object {$_.SwitchName -eq $LANSwitch} | Remove-VMNetworkAdapter -Force

    # Add WAN adapter (e.g., eth0 in router OS)
    Add-VMNetworkAdapter -VMName $VMName -Name "WAN" -SwitchName $WANSwitch

    # Add LAN adapter (e.g., eth1 in router OS)
    Add-VMNetworkAdapter -VMName $VMName -Name "LAN" -SwitchName $LANSwitch

    # Enable MAC address spoofing on LAN adapter if you plan to use it as a DHCP/NAT router,
    # and other VMs/devices will connect through it. This is often required for virtual routers.
    Set-VMNetworkAdapter -VMName $VMName -Name "LAN" -MacAddressSpoofing On

    Write-Host "Successfully configured WAN and LAN network adapters." -ForegroundColor Green
}
catch {
    Write-Error "Failed to configure network adapters. Check SwitchName validity."
    Exit
}

# --- FINAL STEPS ---

## 5. Start VM and Connect
Write-Host "`n-- 5. Starting Virtual Machine --" -ForegroundColor Green
Start-VM -Name $VMName
Write-Host "VM started. Attempting to connect..." -ForegroundColor Green
vmconnect localhost $VMName
#endregion
# ==================================================================
#region * Define Menu Items *
# ==================================================================
$MenuItems = @(
    [PSCustomObject]@{  Id      = ''; Name = '';              Enabled = $true
                        Key     = ''
                        Help    = ''
                        Type    = ''
                        Action  = {  } }
    [PSCustomObject]@{  Id      = ''; Name = '';              Enabled = $true
                        Key     = ''
                        Help    = ''
                        Type    = ''
                        Action  = {  } }
    [PSCustomObject]@{  Id      = ''; Name = '';              Enabled = $true
                        Key     = ''
                        Help    = ''
                        Type    = ''
                        Action  = {  } }
    [PSCustomObject]@{ Id     = 'Q'; Name = 'Quit Menu';                        Enabled = $true
                      Key     = 'Q'
                      Help    = 'Exit menu'
                      Type    = 'Meta'
                      Action  = { return 'quit' } }
)
#endregion
# ==================================================================
#region * Run Menu *
# ==================================================================
# Explicitly define the desired menu title
$MenuTitleExplicit = ""

if (-not [string]::IsNullOrWhiteSpace($MenuTitleExplicit)) {
    $FinalMenuTitle = $MenuTitleExplicit
} else {
    $FinalMenuTitle = Get-MenuTitle
    Write-Verbose "No explicit menu title defined. Falling back to title derived from Get-MenuTitle: '$FinalMenuTitle'."
}

if (Get-Command -Name Show-InteractiveMenu -ErrorAction SilentlyContinue) {
    Show-InteractiveMenu -MenuData $MenuItems -MenuTitle $FinalMenuTitle
} else {
    Write-Error "The Show-InteractiveMenu function was not loaded from InteractiveMenu.psm1. Cannot run menu."
}
#endregion
