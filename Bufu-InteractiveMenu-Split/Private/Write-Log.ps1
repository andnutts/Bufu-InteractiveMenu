function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet('Info', 'Warning', 'Error', 'Debug')]
        [string]$Level,
        [Parameter(Mandatory=$true)]
        [string]$Message
    )
    $logFile = Get-CurrentLogFile
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "$timestamp [$Level] $Message"
    if (-not (Test-Path $LogDirectory)) {
        New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
    }
    Add-Content -Path $logFile -Value $logEntry -Encoding UTF8
    Cleanup-LogFiles
}
