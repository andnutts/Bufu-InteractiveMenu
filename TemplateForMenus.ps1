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
#
# Place your functions for your script
#
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
