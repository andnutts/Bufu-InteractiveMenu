function Read-YesNo {
    <#
    .SYNOPSIS
        Prompts the user for a Yes/No answer and forces a valid choice.
    .PARAMETER Message
        The message displayed to the user.
    .OUTPUTS
        [bool] - $true if 'y' or 'Y' is entered, $false if 'n' or 'N' is entered.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )
    while ($true) {
        $response = Read-Host -Prompt "$Message (Y/N)"
        if ($response -match '^[Yy]$') { return $true }
        if ($response -match '^[Nn]$') { return $false }
        
        # NOTE: Replacing custom 'Write-Color' with the standard 'Write-Warning' for portability.
        Write-Warning "Invalid input. Please enter Y or N."
    }
}