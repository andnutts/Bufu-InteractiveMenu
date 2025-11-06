function Confirm-YesNo {
    <#
    .SYNOPSIS
        Prompts the user for a Yes/No answer, defaulting to 'No' on non-Y/y input.
    .PARAMETER Message
        The message displayed to the user. Defaults to 'Proceed?'.
    .PARAMETER ConfirmFunction
        Allows overriding the default read mechanism with a custom ScriptBlock.
    .OUTPUTS
        [bool] - $true if 'y' or 'Y' is entered, otherwise $false.
    #>
    param(
        [string]$Message = 'Proceed?',
        [ScriptBlock]$ConfirmFunction = $null
    )

    if (-not $ConfirmFunction) {
        # Default behavior: Match 'y' or 'Y'. Any other input, including empty, returns $false.
        $ConfirmFunction = { param($m) (Read-Host "$m (y/N)") -match '^(y|Y)' }
    }

    # Execute the confirmation logic.
    return & $ConfirmFunction $Message
}