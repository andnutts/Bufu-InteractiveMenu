# ==================================================================
# Dynamically load functions from Public and Private folders
# ==================================================================
# Resolve the module file path relative to this script
# ==================================================================
$moduleRoot = Split-Path -Parent $PSCommandPath
# ==================================================================
# Load Private functions (not exported)
# ==================================================================
Get-ChildItem -Path (Join-Path $moduleRoot 'Private') -Filter *.ps1 -Recurse |
    ForEach-Object {
        . $_.FullName
    }
# ==================================================================
# Load Public functions (exported)
# ==================================================================
$publicFunctions = Get-ChildItem -Path (Join-Path $moduleRoot 'Public') -Filter *.ps1 -Recurse |
    ForEach-Object {
        . $_.FullName
        # Return function name(s) defined in the file
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$null, [ref]$null)
        $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true).Name
    }
# ==================================================================
# Export only the public functions
# ==================================================================
Export-ModuleMember -Function $publicFunctions
# SIG # Begin signature block
# MIIFvwYJKoZIhvcNAQcCoIIFsDCCBawCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBHwYm5OARBqyU1
# KzsX3+SVKIoC0L2yTd7SfqcOFJLJMKCCAyYwggMiMIICCqADAgECAhBTL0G9/1qW
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
# LwYJKoZIhvcNAQkEMSIEILCGlwPNPc49ARxioQJ9wxvgzIHBtox6X45IBZBy1wCE
# MA0GCSqGSIb3DQEBAQUABIIBAFEQYSJufFOy5PF7k11E+/M+6lbWDkWWHCWRIAMs
# Ajbv24HEoTvgDtW7FdU1mYPcmTJvhwYzyV380qNph5fEtpJ0Vm6QwIxmOHy26/NR
# mE2X14PPrk0yOiu2XrFGLHR3T0FAgER20GIlzvsxaHOjpCfAODRT4I/VVexYOOC0
# O5cGwVLdFeU85WCh2l7WW9o7HWsA+/BGpZ/Zt1TdtwQ5uH8o5XQ/2bnQ4/SzRk0j
# ucX8zSsE/STZALCHqni1nMmQHrZciqQR0r/MDa1mRdByajaipcPe+PfyyFFnQY6Y
# S7A+RUfqg4uOTZB+eD2vrYcFlMaItN4OEiz174BXcN2XSQ0=
# SIG # End signature block
