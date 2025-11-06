function Cleanup-LogFiles {
    $allLogs = Get-ChildItem -Path $LogDirectory -Filter $LogFilePattern | Sort-Object CreationTime -Descending
    #region --- Size Limit Check (optional: can be resource intensive on large directories) ---
    $maxSize = 5MB
    $largeFiles = $allLogs | Where-Object { $_.Length -gt $maxSize } | Sort-Object Length -Descending
    foreach ($file in $largeFiles) {
        Remove-Item -Path $file.FullName -Force -ErrorAction SilentlyContinue
    }
    #endregion
    #region --- Count Limit Check ---
    if ($allLogs.Count -gt $script:MaxLogFiles) {
        $filesToDelete = $allLogs | Select-Object -Skip $script:MaxLogFiles
        foreach ($file in $filesToDelete) {
            Remove-Item -Path $file.FullName -Force -ErrorAction SilentlyContinue
        }
    }
    #endregion
}