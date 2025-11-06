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
    param(
        [Parameter(Mandatory = $false)]
        [string]$Path
    )
    #region --- Try caller's PSCommandPath (script scope) ---
    if (-not $Path) {
        $callerPSCommandPath = (Get-Variable -Name PSCommandPath -Scope 1 -ErrorAction SilentlyContinue).Value
        if ($callerPSCommandPath) {
            $Path = $callerPSCommandPath
        }
    }
    #endregion
    #region --- Search the call stack for the first frame with a ScriptName ---
    if (-not $Path) {
        $callStack = Get-PSCallStack
        foreach ($frame in $callStack) {
            if ($frame.ScriptName) {
                $Path = $frame.ScriptName
                break
            }
        }
    }
    #endregion
    #region --- This invocation's script or command path ---
    if (-not $Path) {
        if ($MyInvocation.ScriptName) {
            $Path = $MyInvocation.ScriptName
        } elseif ($MyInvocation.MyCommand.Path) {
            $Path = $MyInvocation.MyCommand.Path
        } elseif ($MyInvocation.MyCommand.Definition) {
            $Path = $MyInvocation.MyCommand.Definition
        }
    }
    #endregion
    #region --- Fallback to current directory path ---
    if (-not $Path) {
        $Path = (Get-Location).Path
    }
    #endregion
    #region --- Use directory name if Path is a container; otherwise file name without extension ---
    if (Test-Path -Path $Path -PathType Container) {
        $baseName = Split-Path -Leaf $Path
    } else {
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($Path)
    }
    #endregion
    # Replace separators with spaces and insert spaces before camel-case capitals
    $withSpaces = $baseName -replace '[-_]', ' '
    $title = ($withSpaces -creplace '([a-z0-9])([A-Z])', '$1 $2').Trim()
    return $title
}