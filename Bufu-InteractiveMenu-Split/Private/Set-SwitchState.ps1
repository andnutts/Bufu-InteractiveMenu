function Set-SwitchState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][array]$MenuSwitches,
        [Parameter(Mandatory)][string]$Id,
        [Parameter()][object]$State
    )
    $s = Get-SwitchById -MenuSwitches $MenuSwitches -Id $Id
    if (-not $s) { throw "Switch '$Id' not found." }
    switch ($s.Type) {
        'Toggle' { $new = if ($PSBoundParameters.ContainsKey('State')) { [bool]$State } else { -not [bool]$s.State } }
        'Choice' { if (-not $PSBoundParameters.ContainsKey('State')) { throw "Must supply -State for Choice type." }; $new = $State }
        default { $new = if ($PSBoundParameters.ContainsKey('State')) { $State } else { -not [bool]$s.State } }
    }
    $s.State = $new
    return $s.State
}