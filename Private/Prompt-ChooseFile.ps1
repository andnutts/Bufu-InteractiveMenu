function Prompt-ChooseFile {
    param(
        [string]$Message = 'Choose a .psm1 file',
        [bool]$AllowFilesystemSearch = $true,
        [ScriptBlock]$PromptFunction = $null
    )

    if (-not $PromptFunction) {
        $PromptFunction = {
            param($m,$a)
            if (Get-Command Out-GridView -ErrorAction SilentlyContinue) {
                Get-ChildItem -Path (Get-Location) -Filter '*.psm1' -Recurse -ErrorAction SilentlyContinue |
                    Select-Object -ExpandProperty FullName | Out-GridView -Title $m -PassThru
            } else {
                Read-Host "$m`n(enter full path or blank to cancel)"
            }
        }
    }

    return & $PromptFunction $Message $AllowFilesystemSearch
}