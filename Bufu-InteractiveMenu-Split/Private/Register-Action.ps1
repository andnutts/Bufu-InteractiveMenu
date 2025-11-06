function Register-Action {
    param([string]$Id, [ScriptBlock]$Script)
    if (-not $Id) { throw 'Id required' }
    $ActionRegistry[$Id] = $Script
}