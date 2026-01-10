function Write-Colored {
    param(
        [string]$Text,
        [ConsoleColor]$Fg = 'White',
        [ConsoleColor]$Bg = 'DarkBlue',
        # Alignment (Left, Centered, Right)
    )
    $origFg = [Console]::ForegroundColor
    $origBg = [Console]::BackgroundColor
    [Console]::ForegroundColor = $Fg
    [Console]::BackgroundColor = $Bg
    [Console]::Write($Text)
    [Console]::ForegroundColor = $origFg
    [Console]::BackgroundColor = $origBg
}


make functions: Write-Color with alignment option and function Show-Header

# noqa PSAvoidUsingWriteHost
function Write-Color {
    <#
      .SYNOPSIS
        Writes a timestamped, colored log entry, rotates files, and enforces retention.
      .DESCRIPTION
        Outputs each line as [YYYY-MM-DD HH:MM:SS] [LEVEL] Message in color.
        Supports DEBUG, INFO, WARN, ERROR, LOG levels.
        Rotates when the log file exceeds MaxSize (default 1MB).
        Keeps only the newest MaxFiles logs, deleting older ones.
        Emits verbose messages on rotation and deletion.
      .PARAMETER Message
          The text of the log entry to write.
      .PARAMETER Level
          The severity level of the message. Common values include DEBUG, INFO, WARN, ERROR.
          Defaults to 'INFO'.
      .PARAMETER MaxSize
          The maximum size of the log file before rotation. Accepts 'KB', 'MB', or 'GB'. Defaults to 'MB'.
      .PARAMETER LogDirectory
          Directory where the log file resides. If it doesn’t exist, the function attempts to create it.
          Defaults to the value of $script:LogDirectory.
      .PARAMETER LogName
          Base name (filename) for the log (without extension). On rotation, a timestamp is appended.
          Defaults to the value of $script:LogName.
      .EXAMPLE
          # Basic INFO-level entry
          Write-Color -Message 'Startup complete.'
      .EXAMPLE
          # Rotate when log > 100 MB
          Write-Color -Message 'Batch import done.' -Level INFO -MaxSize MB -LogDirectory 'C:\Logs' -LogName 'AppLog'
      .EXAMPLE
          # Write an ERROR and see the unauthorized/access exception handler fire if disk is full
          Write-Color -Message 'Could not connect to DB' -Level ERROR
      .INPUTS
          None. This function writes directly to the filesystem and host.
      .OUTPUTS
          None. On error, writes an error record to the host.
      .NOTES
          • Uses -ErrorAction Stop on all file cmdlets and catches specific .NET exceptions
          • Ensures that both FileStream and StreamWriter are disposed in the finally block
          • Rotated files are renamed as <LogName>.<yyyyMMddHHmmss>.log
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet("DEBUG","INFO","WARN","ERROR","LOG")]
        [string]                        $Level,
        [Parameter(Mandatory)]
        [string]                        $Message,
        [ConsoleColor]                  $Color,
        [string]                        $LogFile  = "C:\Logs\MenuOutputModule.log",
        [int]                           $MaxFiles = 10,
        [ValidateSet('KB', 'MB', 'GB')]
        [string]                        $MaxSize  = 'MB'
    )
    $LogFile = Join-Path -Path $LogDirectory -ChildPath "$LogName.log"
    $sizeInBytes = switch ($MaxSize) { # Calculate size in bytes
        'KB' { 1KB }
        'MB' { 1MB }
        'GB' { 1GB }
        default { 1MB }
    }
    $stamp    = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logEntry = "[$stamp] [$Level] $Message"
    switch ($Level) { # Determine actual color
        'INFO'  { $clr = $Color ?? 'Green'    }
        'WARN'  { $clr = $Color ?? 'Yellow'   }
        'ERROR' { $clr = $Color ?? 'Red'      }
        'DEBUG' { $clr = $Color ?? 'DarkGray' }
        'LOG'   { $clr = $Color ?? 'Cyan'     }
    }
    try { # Ensure log folder exists
        if (-not (Test-Path $LogDirectory)) {
            New-Item -Path $LogDirectory -ItemType Directory | Out-Null
        }
    }
    catch [System.UnauthorizedAccessException] {
        Write-Error "Permission denied to create log directory '$LogDirectory'. Check folder permissions."
        return
    }
    catch {
        Write-Error "An unexpected error occurred while creating directory '$LogDirectory': $_"
        return
    }
    if (Test-Path $LogFile) { # Rotate log if it exceeds MaxSize
        $size = (Get-Item $LogFile).Length
        if ($size -gt $sizeInBytes) { # Construct the new archived filename using the base name and a timestamp
            $baseName     = [System.IO.Path]::GetFileNameWithoutExtension($LogFile)
            $extension    = [System.IO.Path]::GetExtension($LogFile)
            $archivedName = Join-Path -Path $LogDirectory -ChildPath "$baseName.$(Get-Date -Format 'yyyyMMdd_HHmmss')$extension"
            try {
                Rename-Item -Path $LogFile -NewName $archivedName -ErrorAction Stop
                Write-Verbose "Rotated log file to '$archivedName'."
            }
            catch [System.UnauthorizedAccessException] {
                Write-Error "Permission denied to rotate log file. Check folder permissions."
            }
            catch {
                Write-Error "An unexpected error occurred during file rotation: $_"
            }
            try { # Retention: delete oldest files beyond MaxFiles
                $rotatedLogs = Get-ChildItem -Path $LogDirectory -Filter "$baseName.*$extension" |
                               Sort-Object LastWriteTime -Descending
                if ($rotatedLogs.Count -gt $MaxFiles) {
                    $toDelete = $rotatedLogs | Select-Object -Skip $MaxFiles
                    foreach ($old in $toDelete) {
                        Remove-Item -Path $old.FullName -Force -ErrorAction Stop
                        Write-Verbose "Deleted old log file '$($old.Name)'."
                    }
                }
            }
            catch [System.UnauthorizedAccessException] {
                Write-Error "Permission denied to delete old log files. Check folder permissions."
            }
            catch {
                Write-Error "An unexpected error occurred during log retention: $_"
            }
        }
    }
    else {
        try { # Create a new log file if it doesn't exist
            New-Item -Path $LogFile -ItemType File | Out-Null
        }
        catch [System.UnauthorizedAccessException] {
            Write-Error "Permission denied to create log file '$LogFile'. Check folder permissions."
        }
    }
    try { # Append to file
        Add-Content -Path $LogFile -Value $logEntry -ErrorAction Stop
    }
    catch [System.UnauthorizedAccessException] {
        Write-Error "Permission denied to write to log file '$LogFile'. Check folder permissions."
    }
    catch [System.IO.IOException] {
        Write-Error "An I/O error occurred while writing to log file '$LogFile' (e.g., disk full)."
    }
    catch {
        Write-Error "An unexpected error occurred while writing to log file '$LogFile': $_"
    }
    switch ($Level) {  # Write to host
        'INFO'  { Write-Host    $logEntry -ForegroundColor $clr }
        'LOG'   { Write-Host    $logEntry -ForegroundColor $clr }
        'WARN'  { Write-Warning $Message }
        'ERROR' { Write-Error   $Message }
        'DEBUG' { Write-Debug   $Message }
    }
}

function Show-Header {
    <#
      .SYNOPSIS
        Displays the script’s title banner with optional subtitle/version.
      .PARAMETER Subtitle
        A short line to show beneath the title (e.g. version or tagline).
    #>
    param(
        [string]$Title,
        [string]$Subtitle
    )
    $finalTitle = if ([string]::IsNullOrWhiteSpace($Title)) {
        "📦 " + (Get-ScriptTitle)
    } else {
        "📦 $Title"
    }
    $lineLength = $decoratedTitle.Length + 5
    $underline = '─' * $title.Length
    $spaceline = '=' * $title.Length
    Write-Color -Message $spaceline     -Color Green    -Align Center
    Write-Color -Message $finalTitle    -Color Cyan     -Align Center
    Write-Color -Message $spaceline     -Color Green    -Align Center
    if ($Subtitle) {
        Write-Color -Message $Subtitle  -Color DarkGray -Align Center
        Write-Color -Message $underline -Color Blue     -Align Center
    } else {
        Write-Color -Message $underline -Color Blue     -Align Center
    }
}

After Show first 20 lines of the file and Show all lines of the file  wait then show menu again.
after selecting any menu options besides Exit, then clear host and then show Header and show selected menu option
