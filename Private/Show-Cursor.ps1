function Show-Cursor {
    <#
      .SYNOPSIS
          Shows the console cursor if RawUI is supported.
      .DESCRIPTION
          Sets the console cursor visibility to true, if the host supports RawUI.
    #>
    if (Test-SupportsRawUI) {
        $Host.UI.RawUI.CursorVisible = $true
    }
}