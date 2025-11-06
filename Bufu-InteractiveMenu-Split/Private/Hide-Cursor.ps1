function Hide-Cursor {
    <#
      .SYNOPSIS
          Hides the console cursor if RawUI is supported.
      .DESCRIPTION
          Sets the console cursor visibility to false, if the host supports RawUI.
    #>
    if (Test-SupportsRawUI) {
        $Host.UI.RawUI.CursorVisible = $false
    }
}