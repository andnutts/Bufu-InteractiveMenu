@{
    ModuleVersion = '1.1.0'
    RootModule = 'Bufu-InteractiveMenu.psm1'
    GUID = 'a1b2c3d4-045a-472c-883a-f0f80b2a4e9b'
    Author = 'Nickolas Teuber'
    Description = 'A universal, enhanced PowerShell module for creating sophisticated, interactive console menus, including themed menus, live dashboard menus, and persistent switch management (Debug, DryRun, etc.).'
    #CompanyName = 'Unknown'
    #Copyright = '(c) 2025 Your Name. All rights reserved.'
    PowerShellVersion = '5.1'
    DotNetFrameworkVersion = '4.7.2'
    ProcessorArchitecture = 'Amd64'
    ModuleList = @()
    FileList = @(
        'InteractiveMenu.psm1',
        'README.md'
    )
    FunctionsToExport = @(
        'Invoke-InteractiveMenu',
        'Invoke-DashboardMenu',
        'New-InteractiveMenuTheme',
        'Get-InteractiveMenuSwitch',
        'Set-InteractiveMenuSwitch',
        'Save-InteractiveMenuSwitches',
        'Load-InteractiveMenuSwitches',
        'Reset-InteractiveMenuSwitches'
    )
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()

    PrivateData = @{
        PSData = @{
            # Tags for the PowerShell Gallery
            Tags = @('Menu', 'Interactive', 'Console', 'UI', 'Dashboard', 'Settings', 'State')
            ReleaseNotes = @(
                '1.1.0: Added persistent Switch Management system (Debug, DryRun, etc.) and integrated state into menu headers.'
                '1.0.0: Initial release. Extracted and combined menu systems from various scripts.'
            )
        }
    }
}