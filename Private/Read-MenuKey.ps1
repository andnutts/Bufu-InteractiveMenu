function Read-MenuKey {
    param(
        [Parameter(Mandatory)][array]$MenuSwitches,
        [Parameter(Mandatory)][ValidateSet('Arrow','Numeric')][string]$Mode
    )
    $raw = [System.Console]::ReadKey($true)
    $char = ''
    try { $char = $raw.KeyChar.ToString() } catch { $char = '' }
    $intent = 'Other'
    $switchId = $null
    $number = $null
    switch ($raw.Key) {
        'UpArrow'    { $intent = 'Up' }
        'DownArrow'  { $intent = 'Down' }
        'Enter'      { $intent = 'Enter' }
        'Escape'     { $intent = 'Escape' }
        'Q'          { $intent = 'Quit' }
        default      { }
    }
    if ($char) {
        $u = $char.ToUpper()
        if ($MenuSwitches -and ($MenuSwitches | Where-Object Id -EQ $u)) {
            $intent = 'Switch'
            $switchId = $u
        }
        if ($Mode -eq 'Numeric' -and $char -match '^\d$' -and $intent -ne 'Switch') {
            $n = [int]$char
            if ($n -ge 1) {
                $intent = 'Number'
                $number = $n
            }
        }
    }
    return [PSCustomObject]@{
        Key        = $raw.Key
        KeyChar    = $char
        Intent     = $intent
        SwitchId   = $switchId
        Number     = $number
        RawKeyInfo = $raw
    }
}