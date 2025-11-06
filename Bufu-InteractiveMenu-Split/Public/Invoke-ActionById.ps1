function Invoke-ActionById {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][psobject]$Context,
        [hashtable]$Options
    )

    if (-not $ActionRegistry.ContainsKey($Id)) { throw "Action '$Id' not registered" }

    $sb = $ActionRegistry[$Id]

    # Decide call style: prefer context-aware signature if action declares a param
    $usesContextParam = $false
    try {
        $params = $sb.Parameters
        if ($params.Count -gt 0) {
            # If first parameter name looks like 'ctx' or 'Context' or has no name but is positional, assume context-accepting
            $firstName = $params[0].Name
            if ($firstName -match '^(ctx|context|c)$' -or $params[0].Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } ) {
                $usesContextParam = $true
            } else {
                # fallback: if there is at least one parameter, assume it's context
                $usesContextParam = $true
            }
        }
    } catch {
        # If introspection fails, assume old-style (no context param)
        $usesContextParam = $false
    }

    # Call the action and capture result
    $result = $null
    if ($usesContextParam) {
        try {
            $result = & $sb $Context
        } catch {
            throw "Action '$Id' failed: $($_.Exception.Message)"
        }
    } else {
        # Old-style action: invoke without context
        try {
            $result = & $sb
        } catch {
            throw "Action '$Id' failed: $($_.Exception.Message)"
        }
    }

    # If action returned a Context-like PSCustomObject, use it
    if ($result -and ($result -is [psobject]) -and ($result.PSObject.Properties.Name -contains 'Psm1Path' -or $result.PSObject.TypeNames -contains 'System.Management.Automation.PSCustomObject')) {
        return $result
    }

    # No context returned: rehydrate from globals using provided map or default map
    $rehydrateMap = if ($Options -and $Options.RehydrateMap) { $Options.RehydrateMap } else { $DefaultRehydrateMap }

    foreach ($key in $rehydrateMap.Keys) {
        try {
            $val = & $rehydrateMap[$key]
        } catch {
            $val = $null
        }
        if ($null -ne $val) {
            # create or update property on Context
            if ($Context.PSObject.Properties.Match($key).Count -eq 0) {
                $Context | Add-Member -MemberType NoteProperty -Name $key -Value $val
            } else {
                $Context.$key = $val
            }
        }
    }

    # update LastUsed/time
    if ($Context.PSObject.Properties.Match('LastUsed').Count -eq 0) {
        $Context | Add-Member -MemberType NoteProperty -Name 'LastUsed' -Value (Get-Date)
    } else {
        $Context.LastUsed = (Get-Date)
    }

    return $Context
}
