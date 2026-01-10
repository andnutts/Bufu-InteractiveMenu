function Get-MenuTitle {
    <#
        .SYNOPSIS
            Converts a file or folder name into a spaced menu title.
        .DESCRIPTION
            Strips extensions, replaces hyphens/underscores with spaces,
            and inserts spaces between camel-cased words.
        .PARAMETER Path
            Full or relative path to the script file. If omitted, the function
            will attempt to determine the calling script's file name automatically.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $false)][string]$Path)
    if (-not $Path) {
        $callerPSCommandPath = (Get-Variable -Name PSCommandPath -Scope 1 -ErrorAction SilentlyContinue).Value
        if ($callerPSCommandPath) {
            $Path = $callerPSCommandPath
        }
    }
    if (-not $Path) {
        $callStack = Get-PSCallStack
        foreach ($frame in $callStack) {
            if ($frame.ScriptName) {
                $Path = $frame.ScriptName
                break
            }
        }
    }
    if (-not $Path) {
        if ($MyInvocation.ScriptName) {
            $Path = $MyInvocation.ScriptName
        } elseif ($MyInvocation.MyCommand.Path) {
            $Path = $MyInvocation.MyCommand.Path
        } elseif ($MyInvocation.MyCommand.Definition) {
            $Path = $MyInvocation.MyCommand.Definition
        }
    }
    if (-not $Path) { $Path = (Get-Location).Path }
    if (Test-Path -Path $Path -PathType Container) { $baseName = Split-Path -Leaf $Path }
    else { $baseName = [System.IO.Path]::GetFileNameWithoutExtension($Path) }
    $withSpaces = $baseName -replace '[-_]', ' '
    $title = ($withSpaces -creplace '([a-z0-9])([A-Z])', '$1 $2').Trim()
    return $title
}
