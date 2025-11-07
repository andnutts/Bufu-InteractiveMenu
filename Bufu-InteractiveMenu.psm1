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