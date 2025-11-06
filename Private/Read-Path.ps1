function Read-Path {
    [OutputType([string])]
    param(
        [string]$Message,
        [string]$DefaultPath = $global:LastPath
    )
    if ([string]::IsNullOrWhiteSpace($DefaultPath)) { $DefaultPath = (Get-Location).Path }
    while ($true) {
        $inputPath = Read-Host -Prompt "$Message (Default: '$DefaultPath')"
        if ([string]::IsNullOrWhiteSpace($inputPath)) { $inputPath = $DefaultPath }
        if ($inputPath -match '^\$[A-Za-z_]\w*') { Write-ColoredText "Invalid variable reference." -ForegroundColor Red; continue }
        if (Test-Path -Path $inputPath) { $global:LastPath = $inputPath; return $inputPath }
        else { Write-Color -Message "Path not found. Please try again." -ForegroundColor $Theme.PromptErrorColor }
    }
}