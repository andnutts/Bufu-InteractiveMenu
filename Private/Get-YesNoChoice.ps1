function Get-YesNoChoice {
    <#
    .SYNOPSIS
        The most robust, portable method for getting a Yes/No choice using $host.UI.PromptForChoice().
    .PARAMETER Message
        The main question displayed to the user.
    .PARAMETER Caption
        The title bar text for the prompt window.
    .OUTPUTS
        [bool] - $true if 'Yes' is selected, $false if 'No' is selected.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        [string]$Caption = 'Confirmation'
    )

    # Define the choices with mnemonics (&Yes, &No)
    $choiceYes = [System.Management.Automation.Host.ChoiceDescription]::new('&Yes', 'Select Yes.')
    $choiceNo  = [System.Management.Automation.Host.ChoiceDescription]::new('&No', 'Select No.')
    $choices = [System.Management.Automation.Host.ChoiceDescription[]]($choiceYes, $choiceNo)

    # Prompt the user. The '1' sets the default choice index (0=Yes, 1=No)
    $defaultChoice = 1
    $choiceIndex = $host.UI.PromptForChoice($Caption, $Message, $choices, $defaultChoice)

    # Return $true if the user selected index 0 ('Yes')
    return $choiceIndex -eq 0
}