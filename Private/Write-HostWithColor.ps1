function Write-HostWithColor {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        [ConsoleColor]$ForegroundColor = 'White',
        [ConsoleColor]$BackgroundColor = 'Black'
    )
    Write-Host $Message -ForegroundColor $ForegroundColor -BackgroundColor $BackgroundColor
}