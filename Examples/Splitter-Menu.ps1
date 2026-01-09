<#
    .SYNOPSIS
        Launches the Interactive .psm1 splitter menu.
    .DESCRIPTION
        This script imports the InteractiveMenu.psm1 module and uses it
        to display a menu for splitting a .psm1 file into individual
        function/class files.
#>
#==========================================#
#region ----- Script Functions -----
#==========================================#
#region * Context Helpers *
#==========================================#
function Load-AstAndSource-Context {
    param(
        [Parameter(Mandatory)][psobject]$Context,
        [string]$Path
    )

    # do parsing / dot-sourcing while avoiding hidden global writes
    # (this example assumes Load-AstAndSource original returns parsed objects)
    $parsed = Load-AstAndSource -Path $Path    # reuse existing implementation (side-effects internal to module load)
    # if original Load-AstAndSource mutates environment (e.g., defines functions), you may keep that, but state is recorded in Context
    $Context.Parts = $parsed
    return $Context
}
function Ensure-OutDirs-Context {
    param(
        [Parameter(Mandatory)][psobject]$Context,
        [string]$BaseOut
    )

    if (-not $BaseOut) { throw 'BaseOut required' }
    if (-not (Test-Path $BaseOut)) { New-Item -Path $BaseOut -ItemType Directory -Force | Out-Null }

    # create canonical subfolders you expect
    $dirs = @('Classes','Functions','Private')
    foreach ($d in $dirs) {
        $p = Join-Path $BaseOut $d
        if (-not (Test-Path $p)) { New-Item -Path $p -ItemType Directory -Force | Out-Null }
    }

    $Context.OutDir = $BaseOut
    return $Context
}
function Choose-Psm1File-Context {
    param(
        [Parameter(Mandatory)] [psobject] $Context,
        [bool] $AllowFilesystemSearch = $true,
        [ScriptBlock] $PromptFunction = $null
    )
    if (-not $PromptFunction) { $PromptFunction = { param($m,$a) Prompt-ChooseFile -Message $m -AllowFylesystemSearch $a } }
    $selected = & $PromptFunction 'Select a .psm1 to load' $AllowFilesystemSearch
    if (-not $selected) {
        return $Context
    }
    $Context.Psm1Path = $selected
    if (-not $Context.OutDir) {
        $base = (Split-Path -Leaf $selected) -replace '\.psm1$',''
        $Context.OutDir = Join-Path -Path (Split-Path -Parent $selected) -ChildPath ("$base-Split")
    }
    return $Context
}
#endregion
#==========================================#
#region * Action Registry *
#==========================================#
$ActionRegistry = @{}
function Register-Action {
    param([string]$Id, [ScriptBlock]$Script)
    if (-not $Id) { throw 'Id required' }
    $ActionRegistry[$Id] = $Script
}
# Default rehydration mapping: map well-known globals into Context keys
$DefaultRehydrateMap = @{
    'Psm1Path'   = { if (Get-Variable -Name 'Psm1Path' -Scope Script -ErrorAction SilentlyContinue) { (Get-Variable -Name 'Psm1Path' -Scope Script).Value } elseif (Get-Variable -Name 'Psm1Path' -Scope Global -ErrorAction SilentlyContinue) { (Get-Variable -Name 'Psm1Path' -Scope Global).Value } else { $null } }
    'OutDir'     = { if (Get-Variable -Name 'GlobalConfig' -Scope Script -ErrorAction SilentlyContinue) { $g=(Get-Variable -Name 'GlobalConfig' -Scope Script).Value; if ($g -and $g.OutDir) { $g.OutDir } else { $null } } elseif (Get-Variable -Name 'GlobalConfig' -Scope Global -ErrorAction SilentlyContinue) { $g=(Get-Variable -Name 'GlobalConfig' -Scope Global).Value; if ($g -and $g.OutDir) { $g.OutDir } else { $null } } else { $null } }
    'LastUsed'   = { (Get-Date) }
}
# Invoke-ActionById: compatible wrapper
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
#endregion
#==========================================#
#region * Helpers *
#==========================================#
function Load-AstAndSource {
    param([string]$Path)
    Write-Host "Loading AST and source for: $Path"
    
    # --- This is a placeholder ---
    # In a real script, you'd parse the file content:
    # $tokens = $null
    # $errors = $null
    # $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    # $script:Source = Get-Content -Path $Path -Raw
    # $script:FunctionAsts = $ast.FindAll( { $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    # $script:ClassAsts = $ast.FindAll( { $args[0] -is [System.Management.Automation.Language.TypeDefinitionAst] -and $args[0].IsClass }, $true)
    # Write-Host "Found $($script:FunctionAsts.Count) functions and $($script:ClassAsts.Count) classes."
    # -----------------------------

    # --- Faking ASTs for demonstration ---
    Write-Warning "Load-AstAndSource is a placeholder. Using dummy data."
    $script:FunctionAsts = @(
        [PSCustomObject]@{ Name = 'Get-Foo'; Extent = [PSCustomObject]@{ Text = 'function Get-Foo { ... }'; StartLine = 1; StartOffset = 0 } }
        [PSCustomObject]@{ Name = 'Set-Bar'; Extent = [PSCustomObject]@{ Text = 'function Set-Bar { ... }'; StartLine = 10; StartOffset = 200 } }
    )
    $script:ClassAsts = @(
        [PSCustomObject]@{ Name = 'MyCoolClass'; Extent = [PSCustomObject]@{ Text = 'class MyCoolClass { ... }'; StartLine = 20; StartOffset = 400 } }
    )
    $script:Source = "function Get-Foo { ... } `n`r #... `n`r function Set-Bar { ... } `n`r #... `n`r class MyCoolClass { ... }"
    Write-Host "Loaded dummy AST with 2 functions and 1 class."
    # -----------------------------------

    $script:Psm1Path = $Path # Store Psm1Path in script scope
    if (-not $GlobalConfig.OutDir) {
         $GlobalConfig.OutDir = Join-Path (Split-Path -Parent $Path) "$((Split-Path -Leaf $Path) -replace '\.psm1$','')-Split"
    }
    Write-Host "Output directory set to: $($GlobalConfig.OutDir)"
}
function Choose-Psm1File {
    param(
        [string]$StartDir = (Get-Location),
        [switch]$AllowFilesystemSearch
    )

    $psm1s = Get-ChildItem -Path $StartDir -Filter *.psm1 -File -ErrorAction SilentlyContinue
    if ($psm1s -and $psm1s.Count -gt 0) {
        if ($psm1s.Count -eq 1) { return $psm1s[0].FullName }
        for ($i = 0; $i -lt $psm1s.Count; $i++) { Write-Host ("[{0}] {1}" -f ($i+1), $psm1s[$i].Name) }
        $choice = Read-Host "Enter number of file to use (or leave empty to cancel or press S to search filesystem)"
        if (-not $choice) { return $null }
        if ($choice -match '^[sS]$') {
            $AllowFilesystemSearch = $true
        } elseif ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $psm1s.Count) {
            return $psm1s[[int]$choice - 1].FullName
        } else {
            Write-Warning "Invalid selection."
            return $null
        }
    }

    if (-not $AllowFilesystemSearch) {
        $yn = Read-Host "No .psm1 found in $StartDir. Search filesystem for .psm1 files? (y/n) [y]"
        if (-not $yn) { $yn = 'y' }
        if ($yn -notmatch '^(y|Y)') { return $null }
    }

    try {
        $home = $env:USERPROFILE
        if (-not $home) { $home = [Environment]::GetFolderPath('UserProfile') }
        $found = Search-DirectoryForPsm1 -Path $home -Recurse -MaxDepth 6 -SkipDirs @('.git','node_modules','bin','obj') -IncludeHidden:$false -Pick -UseFzfIfAvailable
        if ($found -and ($found -is [System.IO.FileInfo])) { return $found.FullName }
        if ($found -and ($found -is [System.String])) { return $found }
        if ($found -and ($found.Count -gt 0)) { return $found[0].FullName }
        Write-Warning "No .psm1 files found by filesystem search."
        return $null
    } catch {
        Write-Warning "Filesystem search failed: $($_.Exception.Message)"
        $manual = Read-Host "Enter full path to a .psm1 file or leave empty to cancel"
        if ($manual -and (Test-Path $manual)) { return (Resolve-Path $manual).Path }
        return $null
    }
}
function Interactive-MoveFunctions {
    if (-not $script:FunctionAsts -or $script:FunctionAsts.Count -eq 0) { Write-Host "No functions to move."; return }
    $display = $script:FunctionAsts | ForEach-Object { ($_.Extent.Text -split "`r?`n",2)[0].Trim() }
    $selected = Select-Multi -Items $display -Prompt "Select functions to move"
    if (-not $selected -or $selected.Count -eq 0) { Write-Host "No selection."; return }
    $selectedAsts = @()
    foreach ($s in $selected) { $selectedAsts += ($script:FunctionAsts | Where-Object { ($_.Extent.Text -split "`r?`n",2)[0].Trim() -eq $s } | Select-Object -First 1).Extent }
    $applyAll = $true
    $ans = Read-Host "Apply same destination to all? (y/n) [y]"; if (-not $ans) { $ans='y' }; if ($ans -notmatch '^(y|Y)') { $applyAll = $false }
    $destMap = @{}
    if ($applyAll) {
        $dest = Read-Host "Destination (Public / Private / Class) [Private]"; if (-not $dest) { $dest='Private' }
        foreach ($ast in $selectedAsts) { $destMap[$ast.StartOffset] = $dest }
    } else {
        foreach ($ast in $selectedAsts) {
            $preview = ($ast.Text -split "`r?`n",2)[0].Trim()
            $d = Read-Host "Destination for '$preview' (Public / Private / Class) [Private]"; if (-not $d) { $d='Private' }
            $destMap[$ast.StartOffset] = $d
        }
    }
    foreach ($ast in $selectedAsts) {
        $raw = $ast.Text; $norm = Normalize-FunctionText -rawText $raw
        $name = if ($norm -match 'function\s+([^\s{(]+)') { $matches[1] } else { "Function_$($ast.StartLine)" }
        $safeName = $name -replace '[\\/:*?"<>| ]','_'
        $dir = switch ($destMap[$ast.StartOffset].ToLower()) { 'public' { $script:PublicDir } 'class' { $script:ClassDir } default { $script:PrivateDir } }
        $out = Join-Path $dir ("$safeName.ps1")
        $norm.Trim() | Set-Content -Path $out -Encoding UTF8
        Write-Host "Wrote $out"
    }
    Load-AstAndSource -Path $script:Psm1Path # Use script-scoped path
}
function Export-AllClasses {
    if (-not $script:ClassAsts -or $script:ClassAsts.Count -eq 0) { Write-Host "No classes present."; return }
    foreach ($c in $script:ClassAsts) {
        $name = $c.Name -replace '[\\/:*?"<>| ]','_'
        $out = Join-Path $script:ClassDir ("$name.ps1")
        $c.Extent.Text.Trim() | Set-Content -Path $out -Encoding UTF8
        Write-Host "Wrote $out"
    }
}
function Generate-Index {
    $publicFiles = Get-ChildItem -Path $script:PublicDir -Filter *.ps1 -File -ErrorAction SilentlyContinue
    if (-not $publicFiles) { Write-Host "No Public files to index."; return }
    $lines = @()
    foreach ($p in $publicFiles) {
        $lines += ". `$PSScriptRoot\Public\$($p.Name)"
    }
    $indexPath = Join-Path $GlobalConfig.OutDir (Split-Path -Leaf $script:Psm1Path -replace '\.psm1$','.psm1')
    $lines | Set-Content -Path $indexPath -Encoding UTF8
    Write-Host "Wrote index module: $indexPath"
}
function Write-Helpers {
    $usedSpans = New-Object System.Collections.Generic.List[System.Management.Automation.Language.TextRange]
    foreach ($f in $script:FunctionAsts) { $usedSpans.Add($f.Extent) }
    foreach ($c in $script:ClassAsts) { $usedSpans.Add($c.Extent) }
    $lines = $script:Source -split "`r?`n"
    $keep = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $lines.Length; $i++) {
        $lineNum = $i + 1; $inside = $false
        foreach ($u in $usedSpans) { if ($lineNum -ge $u.StartLine -and $lineNum -le $u.EndLine) { $inside = $true; break } }
        if (-not $inside) { $keep.Add($lines[$i]) }
    }
    $helpersText = $keep -join "`r`n"
    if ($helpersText.Trim()) {
        $hPath = Join-Path $script:PrivateDir '_helpers.ps1'
        $helpersText.Trim() | Set-Content -Path $hPath -Encoding UTF8
        Write-Host "Wrote $hPath"
    } else { Write-Host "No helper content to write." }
}
function Remove-MovedFromSource {
    <#
        .SYNOPSIS
            Removes functions and classes from the source .psm1 file that
            have been extracted to the Public/Private/Class directories.
    #>
    $bak = "$($script:Psm1Path).bak.$((Get-Date).ToString('yyyyMMddHHmmss'))"
    Copy-Item -Path $script:Psm1Path -Destination $bak -Force
    Write-Host "Backup created: $bak"

    # 1. Get all files/names that have been moved
    $allMovedFiles = Get-ChildItem -Path $script:PublicDir,$script:PrivateDir,$script:ClassDir -Filter *.ps1 -File -ErrorAction SilentlyContinue
    if (-not $allMovedFiles) { Write-Host "No moved files found to remove from source."; return }
    $movedNames = $allMovedFiles | ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Name) } | Select-Object -Unique

    # 2. Find all Function/Class AST nodes that match these names
    $astsToRemove = New-Object System.Collections.Generic.List[System.Management.Automation.Language.Ast]
    foreach ($name in $movedNames) {
        # Find functions
        $astsToRemove.AddRange( ($script:FunctionAsts | Where-Object { $_.Name -eq $name }) )
        # Find classes
        $astsToRemove.AddRange( ($script:ClassAsts | Where-Object { $_.Name -eq $name }) )
    }

    if ($astsToRemove.Count -eq 0) {
        Write-Warning "Found moved files, but couldn't match them to AST nodes in the source. No changes made."
        return
    }

    # 3. Get the extents (text ranges) of these AST nodes
    $usedSpans = New-Object System.Collections.Generic.List[System.Management.Automation.Language.TextRange]
    foreach ($ast in $astsToRemove) { $usedSpans.Add($ast.Extent) }

    # 4. Rebuild the source file, *excluding* lines within these extents
    $lines = $script:Source -split "`r?`n"
    $keep = New-Object System.Collections.Generic.List[string]
    $removedCount = 0

    for ($i = 0; $i -lt $lines.Length; $i++) {
        $lineNum = $i + 1; $inside = $false
        foreach ($u in $usedSpans) {
            if ($lineNum -ge $u.StartLine -and $lineNum -le $u.EndLine) {
                $inside = $true
                # Track that we are actively removing the first line of a block
                if ($lineNum -eq $u.StartLine) { $removedCount++ }
                break
            }
        }
        if (-not $inside) { $keep.Add($lines[$i]) }
    }

    # 5. Write the modified content back
    $newContent = $keep -join "`r`n"
    $newContent | Set-Content -Path $script:Psm1Path -Encoding UTF8

    Write-Host "Removed $removedCount function/class definition(s) from source. Original backed up at $bak"
    # 6. Reload the AST since the source has changed
    Load-AstAndSource -Path $script:Psm1Path
}
function Ensure-OutDirs {
    param([string]$BaseOut)
    $script:PublicDir = Join-Path $BaseOut 'Public'; $script:PrivateDir = Join-Path $BaseOut 'Private'; $script:ClassDir = Join-Path $BaseOut 'Class'
    @($script:PublicDir, $script:PrivateDir, $script:ClassDir) | ForEach-Object { 
        if (-not (Test-Path $_)) {
            New-Item -Path $_ -ItemType Directory -Force | Out-Null 
        }
    }
}
# ------------------------------------------
function List-Functions {
    if (-not $script:FunctionAsts) { Write-Host "No module loaded or no functions."; return }
    for ($i=0; $i -lt $script:FunctionAsts.Count; $i++) {
        $f = $script:FunctionAsts[$i]; $first = ($f.Extent.Text -split "`r?`n",2)[0].Trim()
        Write-Host ("[{0}] {1}" -f ($i+1), $first)
    }
}
function Select-Multi {
    param([Parameter(Mandatory=$true)][string[]]$Items, [string]$Prompt = "Select items (multi-select)")
    $psfzfFunc = Get-Command -Name Invoke-Fzf -ErrorAction SilentlyContinue
    if ($psfzfFunc) {
        try { return Invoke-Fzf -Items $Items -Multi -Prompt $Prompt } catch { Write-Warning "Invoke-Fzf failed. Falling back." }
    }
    if ($Host.Name -ne 'ServerRemoteHost' -and (Get-Command Out-GridView -ErrorAction SilentlyContinue)) {
        try { return $Items | Out-GridView -Title $Prompt -OutputMode Multiple } catch { Write-Warning "Out-GridView failed." }
    }
    Write-Host $Prompt
    for ($i = 0; $i -lt $Items.Count; $i++) { Write-Host ("[{0}] {1}" -f ($i+1), $Items[$i]) }
    $sel = Read-Host "Enter numbers separated by commas (e.g. 1,3,4) or 'a' for all"
    if ($sel -eq 'a') { return $Items }
    $indexes = $sel -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ - 1 } | Where-Object { $_ -ge 0 -and $_ -lt $Items.Count }
    $result = @(); foreach ($idx in $indexes) { $result += $Items[$idx] }; return $result
}
function Normalize-FunctionText { param([string]$rawText)
    $braceIndex = $rawText.IndexOf('{'); if ($braceIndex -lt 0) { return $rawText.Trim() }
    $header = $rawText.Substring(0, $braceIndex).Trim(); $body = $rawText.Substring($braceIndex)
    if ($header -match '(?i)\bfunction\b') { $header = ($header -replace '(?i)\bfunction\b','').Trim() }
    if ($header -match '^[a-zA-Z]+\s*:\s*(.+)$') { $name = $matches[1].Trim() } else { $name = $header.Trim() }
    $name = $name -replace '\s*\(.*$',''; return "function $name $body"
}
# ------------------------------------------
function Search-DirectoryForPsm1 {
    [CmdletBinding()]
    param(
        [Parameter(Position=0)][string]$Path = (Get-Location),
        [Parameter()][switch]$Recurse,
        [int]$MaxDepth = 6,
        [string[]]$SkipDirs = @('.git','node_modules','bin','obj'),
        [switch]$IncludeHidden = $false,
        [string]$Filter = '*.psm1',
        [switch]$Pick,
        [switch]$UseFzfIfAvailable
    )

    $start = (Resolve-Path -Path $Path -ErrorAction SilentlyContinue)
    if (-not $start) { Throw "Path not found: $Path" }
    $start = $start.Path

    $results = New-Object System.Collections.Generic.List[System.IO.FileInfo]
    $queue = New-Object System.Collections.Generic.Queue[System.Tuple[string,int]]
    $queue.Enqueue([System.Tuple]::Create($start, 0))

    while ($queue.Count -gt 0) {
        $pair = $queue.Dequeue()
        $dir = $pair.Item1
        $depth = $pair.Item2

        try {
            $files = Get-ChildItem -Path $dir -File -Force:($IncludeHidden.IsPresent) -Filter $Filter -ErrorAction Stop
            foreach ($f in $files) { $results.Add($f) }
        } catch { }

        if ($Recurse -and $depth -lt $MaxDepth) {
            try {
                $subdirs = Get-ChildItem -Path $dir -Directory -Force:($IncludeHidden.IsPresent) -ErrorAction Stop
                foreach ($sd in $subdirs) {
                    if ($SkipDirs -and ($SkipDirs -contains $sd.Name)) { continue }
                    $queue.Enqueue([System.Tuple]::Create($sd.FullName, $depth + 1))
                }
            } catch { }
        }
    }

    $arr = $results | Sort-Object -Property FullName

    if ($Pick) {
        $fzf = Get-Command -Name Invoke-Fzf -ErrorAction SilentlyContinue
        if ($UseFzfIfAvailable -and $fzf) {
            try {
                $items = $arr | ForEach-Object { $_.FullName }
                $pick = Invoke-Fzf -Items $items -Prompt 'Select a .psm1 file'
                if ($pick) { return (Get-Item -Path $pick) }
                return $null
            } catch { }
        }

        if ($Host.Name -ne 'ServerRemoteHost' -and (Get-Command Out-GridView -ErrorAction SilentlyContinue)) {
            try {
                $pick = $arr | Select-Object -ExpandProperty FullName | Out-GridView -Title 'Select a .psm1 file' -OutputMode Single
                if ($pick) { return (Get-Item -Path $pick) }
                return $null
            } catch { }
        }

        if (-not $arr -or $arr.Count -eq 0) {
            Write-Host "No .psm1 files found."
            return @()
        }
        for ($i = 0; $i -lt $arr.Count; $i++) {
            Write-Host ("[{0}] {1}" -f ($i+1), $arr[$i].FullName)
        }
        $sel = Read-Host "Enter number of file to pick (or empty to cancel)"
        if ($sel -and $sel -match '^\d+$' -and [int]$sel -ge 1 -and [int]$sel -le $arr.Count) {
            return $arr[[int]$sel - 1]
        }
        return $null
    }

    return ,$arr
}
#endregion
#==========================================#
#endregion
#==========================================#

#==========================================#
#region * Menu configuration *
#==========================================#
$MenuOptions = @(
    [PSCustomObject]@{ Id     = '1'; Name = 'Load/Select PSM1 Module';          Enabled = $true
                      Key     = 'C'
                      Help    = 'Choose a .psm1 and prepare output dirs'
                      Type    = 'PS'
                      Action  = {  $Global:Psm1Path = Choose-Psm1File # Use Global: or $script: scope
                                   if ($Global:Psm1Path) {
                                       Load-AstAndSource -Path $Global:Psm1Path
                                       Ensure-OutDirs -BaseOut $GlobalConfig.OutDir } } }
    [PSCustomObject]@{ Id     = '2'; Name = 'List Parsed Functions';            Enabled = $true
                      Key     = 'L'
                      Help    = 'Show parsed functions from loaded module'
                      Type    = 'PS'
                      Action  = { List-Functions } }
    [PSCustomObject]@{ Id     = '3'; Name = 'Interactive Move Functions';       Enabled = $true
                      Key     = 'I'
                      Help    = 'Interactive multi-select move'
                      Type    = 'PS'
                      Action  = { Interactive-MoveFunctions } }
    [PSCustomObject]@{ Id     = '4'; Name = 'Export All Classes';               Enabled = $true
                      Key     = 'A'
                      Help    = 'Export classes into Class folder'
                      Type    = 'PS'
                      Action  = { Export-AllClasses } }
    [PSCustomObject]@{ Id     = '5'; Name = 'Generate Module Index';            Enabled = $true
                      Key     = 'X'
                      Help    = 'Create index module that dot-sources public members'
                      Type    = 'PS'
                      Action  = { Generate-Index } } # Renamed from Generate-ModuleIndex
    [PSCustomObject]@{ Id     = '6'; Name = 'Write Helper/Misc Code';           Enabled = $true
                      Key     = 'W'
                      Help    = 'Write remaining private helpers'
                      Type    = 'PS'
                      Action  = { Write-Helpers } }
    [PSCustomObject]@{ Id     = '7'; Name = 'Remove Moved from Source';         Enabled = $true
                      Key     = 'R'
                      Help    = 'Modify original .psm1 and create backup after confirmation'
                      Type    = 'PS'
                      Action  = {  if (-not $script:Psm1Path) { # Check script: scope
                                   Write-Warning 'No module loaded.'
                                   return }
                                   $c = Read-Host 'This modifies the source file and creates a backup. Proceed? (y/n) [n]'
                                   if ($c -match '^(y|Y)') {
                                       Remove-MovedFromSource
                                   } else {
                                       Write-Host 'Canceled.' } } }
    [PSCustomObject]@{ Id     = '8'; Name = 'Example: Run CMD Script';          Enabled = $true
                      Key     = 'M'
                      Help    = 'Metadata-only row demonstrating File/Type'
                      Type    = 'CMD'
                      File    = 'mock-script.py'
                      Action  = $null }
    [PSCustomObject]@{ Id     = 'S'; Name = 'Universal Menu Settings';          Enabled = $true
                      Key     = 'S'
                      Help    = 'Configure the interactive menu behavior'
                      Type    = 'PS'
                      Action  = {
                          # This function is imported from the .psm1!
                          # We pass $DefaultSwitches so the settings menu can modify them directly.
                          Show-MenuSettings -MenuSwitches $DefaultSwitches
                      } }
    [PSCustomObject]@{ Id     = 'Q'; Name = 'Quit Menu';                        Enabled = $true
                      Key     = 'Q'
                      Help    = 'Exit menu'
                      Type    = 'Meta'
                      Action  = { return 'quit' } }
)
#endregion
#==========================================#
# Initial load and OutDir setup
#==========================================#
$MyScriptDir = try { Split-Path -Parent $MyInvocation.MyCommand.Path -ErrorAction Stop } catch { (Get-Location).Path }

# IMPORT THE MODULE
try {
    Import-Module -Name (Join-Path $MyScriptDir 'InteractiveMenu.psm1') -Force
} catch {
    Write-Host "ERROR: Failed to import InteractiveMenu.psm1." -ForegroundColor Red
    Write-Host "Please ensure 'InteractiveMenu.psm1' is in the same directory:" -ForegroundColor Red
    Write-Host $MyScriptDir -ForegroundColor Yellow
    Read-Host "Press [Enter] to exit..."
    return
}

# Define script-scoped variables that the functions rely on
$script:Psm1Path = $null
$script:Source = $null
$script:FunctionAsts = @()
$script:ClassAsts = @()
$script:PublicDir = ''
$script:PrivateDir = ''
$script:ClassDir = ''

# GlobalConfig and DefaultSwitches are defined in the imported module,
# but we need to initialize them in this script's scope for the functions here to see them.
# We can grab the defaults from the module.
$DefaultSwitches = $DefaultSwitches # This should now pick up the one from the module
$GlobalConfig = $GlobalConfig       # This should now pick up the one from the module

Show-InteractiveMenu `
    -MenuData $MenuOptions `
    -MenuSwitches $DefaultSwitches `
    -Title "PowerShell Module Splitter" `
    -ScriptDir $MyScriptDir `
    -EnablePersistence

#==========================================#