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
# SIG # Begin signature block
# MIIFvwYJKoZIhvcNAQcCoIIFsDCCBawCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCB6EtFL2Gl4KkZb
# 8hTcNJINFlbgx+ocVBXYwvlg01dFoKCCAyYwggMiMIICCqADAgECAhBTL0G9/1qW
# u0vZWRqoGigBMA0GCSqGSIb3DQEBCwUAMCkxJzAlBgNVBAMMHlNldEVudkludGVy
# YWN0aXZlIENvZGUgU2lnbmluZzAeFw0yNTEyMTExNjE2MDdaFw0zMDEyMTExNjI2
# MDdaMCkxJzAlBgNVBAMMHlNldEVudkludGVyYWN0aXZlIENvZGUgU2lnbmluZzCC
# ASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAMINkqJcrKIzkS6j5yHr4BRQ
# sxbufzzhaTcFk5GPw9MBm2w4728lOUg8XWxF0PB1nNz9SeQnSV+/v7nXE/siXOni
# f77MRhzqjwYvYVNnueXg+En+TeCfLsVJ3xL+/Dum+GDo0MGBA+/Xz/3HTNtMZzHU
# qO92G3t36C8rJaEU0NfV6MOn7pQUcDyNUKXcPnFADMn23V1JhTqYe3DI1/Qe2TJ3
# pFkh72IJ7Zq4fn6egOlYaPbxxOnLA8e4WizW/OEP7SG7gFn/0skeslbB8ICs0U9x
# TdFsUNgK+W1SkJL8LqRTnbG0LqiYBHqa+kzLN7zPAzaCllaZbXkKhl2dz6n89nEC
# AwEAAaNGMEQwDgYDVR0PAQH/BAQDAgeAMBMGA1UdJQQMMAoGCCsGAQUFBwMDMB0G
# A1UdDgQWBBQHDipZfdXTdLr+9/8M/LJlU+lKITANBgkqhkiG9w0BAQsFAAOCAQEA
# QamQPBxTtg+sE9mApfJMOMuFR3iBOJL/7gjgONmbh5vfv6YBX3rF5Povf6bqXgJr
# 37yR1siuZRFw65hprf8mkx47rIRKgDGeJ7/lKtkvJjW1mPFC5TDqGfMcfsSmH8wD
# VcSR8RdTTCP+s3cco6vaAvJHqtFi2omzUbhbPNDExjAvm+6ctauqMmAisfU0xuW+
# SNNz7FdcQbfoVwq9SionBeC6F+phSQM265IGBnTmpkInoedqwwMDejnTmTiLuatr
# 42yxv4IoJcqjjhF5lxT7Vj/RW+MdPGpRoCYDQ0shXOu4vh5RerTIIrS2m8XZl5gN
# N5Vhd+hERzeerNtkHWyD7jGCAe8wggHrAgEBMD0wKTEnMCUGA1UEAwweU2V0RW52
# SW50ZXJhY3RpdmUgQ29kZSBTaWduaW5nAhBTL0G9/1qWu0vZWRqoGigBMA0GCWCG
# SAFlAwQCAQUAoIGEMBgGCisGAQQBgjcCAQwxCjAIoAKAAKECgAAwGQYJKoZIhvcN
# AQkDMQwGCisGAQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUw
# LwYJKoZIhvcNAQkEMSIEINlXOXGxrK8CwRppObR2fIk8thXYJYqCjsqILiUrODLM
# MA0GCSqGSIb3DQEBAQUABIIBAMCtF46aKEbzfmRLJe5XbuYaSh3wJ36Y/XH0RWV3
# Jzk/aF2bP86H9eWrHhR253YpRA5EYWoUE+xoQbYpsFlpCiK3RGkxzpTlmwprCHmG
# HgXzMuIo/JM3HoO9y6ABIAxToRz9KTyIkl3abHuFZjVfGsWZO0H4Dw9kARRi76X4
# Mr4p3T4ASfjNvXUXKW35st2+RXz/I/Xlzd7+4mRfycxuRrSzFSdU7HXPyaLdVgtX
# /KNvW3/CnC3HTj5z2JneIayWJXdBILfogGHt1BB5/6UF1chDC3MNf43adg9PNgVU
# f4FchuTBynpDRsan9iaRYawWdvPXwaxEvPSY0Bo1s2zHTnE=
# SIG # End signature block
