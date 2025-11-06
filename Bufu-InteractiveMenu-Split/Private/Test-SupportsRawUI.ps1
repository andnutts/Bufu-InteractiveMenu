function Test-SupportsRawUI {
    <#
      .SYNOPSIS
          Tests if the current host supports RawUI operations.
      .DESCRIPTION
          Checks if the host's UI supports RawUI features like cursor visibility
          and position manipulation.
      .OUTPUTS
          [bool]
          Returns $true if RawUI is supported, otherwise $false.
      .EXAMPLE
          if (Test-SupportsRawUI) {
              Write-Host "RawUI is supported."
          } else {
              Write-Host "RawUI is not supported."
          }
    #>
    try {
        return $Host.UI.RawUI.CursorVisible -ne $null -and $Host.UI.RawUI.CanSetCursorPosition
    } catch {
        return $false
    }
}