function Get-CurrentLogFile {
    $datePart = Get-Date -Format "yyyyMMdd"
    return
    Join-Path -Path $LogDirectory -ChildPath "ProfileMenu_$datePart.log"
}