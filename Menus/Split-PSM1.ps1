# ==================================================================
# Filename: Split-PSM1.ps1
# Description: Main script for the PC Maintenance and Utility Menu,
# which relies on the InteractiveMenu.psm1 module.
# ==================================================================
<#
    .SYNOPSIS
        Interactive .psm1 splitter with PSFzf-aware search and a menu driven by $MenuOptions.
    .DESCRIPTION
        - Search-DirectoryForPsm1: breadth-first, limited-depth search with interactive pick support.
        - Choose-Psm1File: non-recursive scan, then optional filesystem search using Search-DirectoryForPsm1 (PSFzf/Out-GridView/text fallback).
        - Interactive Move: multi-select functions (Invoke-Fzf if available) and write them to Public/Private/Class folders, normalizing scoped declarations.
        - Other utilities: export classes, generate index, remove moved functions (with backup), write helpers.
#>
# ==================================================================
#region * Import Interactive Menu Module *
# ==================================================================
# Set the path to the InteractiveMenu.psm1 module located in the parent directory
$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
# Assume the module is one level up relative to the Menus folder
$MenuModule = Join-Path (Split-Path $ScriptPath -Parent) 'InteractiveMenu.psm1'

if (Test-Path $MenuModule) {
    . $MenuModule
    Write-Host "[OK] InteractiveMenu.psm1 module loaded." -ForegroundColor Green
} else {
    Write-Error "InteractiveMenu.psm1 not found at '$MenuModule'. Exiting."
    return
}
#endregion
# ==================================================================
#region * Global State & Configuration *
# ==================================================================
# Script-scoped variables to hold the state of the loaded module
$script:Psm1Path = $null
$script:Source = $null
$script:FunctionAsts = $null
$script:ClassAsts = $null
$script:PublicDir = $null
$script:PrivateDir = $null
$script:ClassDir = $null
$GlobalConfig = @{ Psm1Path = $null; OutDir = $null } # Placeholder config object

# Helper function to check if a module is currently loaded
function Check-ModuleLoaded {
    return $script:Psm1Path -ne $null
}
#endregion
# ==================================================================
#region * Helpers (Updated) *
# ==================================================================

function Load-AstAndSource {
    param([string]$Path)
    $Path = (Resolve-Path $Path).Path
    Write-Host "Loading and analyzing: $Path" -ForegroundColor Cyan

    $script:Psm1Path = $Path
   
    try {
        # Read the content and parse the Abstract Syntax Tree (AST)
        $script:Source = Get-Content -Path $Path -Raw
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($script:Source, [ref]$null, [ref]$null).Ast

        # Find all Function and Class definitions
        $script:FunctionAsts = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
        $script:ClassAsts = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.TypeDefinitionAst] -and $args[0].IsClass }, $true)

        # Set Global Configs and Output Paths
        $GlobalConfig.PSM1Path = $Path
        $GlobalConfig.OutDir = Join-Path (Split-Path -Parent $Path) "$((Split-Path -Leaf $Path) -replace '\.psm1$','')-Split"
        $OutDir = $GlobalConfig.OutDir

        # Update script-scoped directories and ensure they exist
        Ensure-OutDirs -BaseOut $OutDir

        Write-Host "[OK] Module loaded. Functions found: $($script:FunctionAsts.Count). Classes found: $($script:ClassAsts.Count)" -ForegroundColor Green
        Write-Host "Split Output Directory: $OutDir" -ForegroundColor Yellow

    } catch {
        Write-Error "Failed to parse AST for '$Path': $($_.Exception.Message)"
        $script:Psm1Path = $null # Clear state on failure
        # Clear other variables on failure
        $script:Source = $null; $script:FunctionAsts = $null; $script:ClassAsts = $null
    }
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
    Load-AstAndSource -Path $script:Psm1Path
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
    $lines += "# This file was auto-generated by Split-PSM1 utility."
    $lines += ""
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
        .DESCRIPTION
            This function is much safer than the regex-based original.
            1. Creates a backup of the source file.
            2. Scans Public, Private, and Class folders for .ps1 files.
            3. Gets the base name (e.g., 'MyFunction') from each file.
            4. Finds all Function and Class AST nodes in the loaded module
               that match these names.
            5. Gathers the 'Extent' (start/end line) for each matched AST node.
            6. Re-builds the source file by keeping only the lines that are
               *outside* the extents of the moved items.
            7. Overwrites the original .psm1 and re-loads the AST.
    #>
    $Psm1Path = $script:Psm1Path
    $OutDir = $GlobalConfig.OutDir
   
    $bak = "$Psm1Path.bak.$((Get-Date).ToString('yyyyMMddHHmmss'))"
    Copy-Item -Path $Psm1Path -Destination $bak -Force
    Write-Host "Backup created: $bak" -ForegroundColor Yellow

    # 1. Get all files/names that have been moved
    $allMovedFiles = Get-ChildItem -Path $script:PublicDir,$script:PrivateDir,$script:ClassDir -Filter *.ps1 -File -ErrorAction SilentlyContinue
    if (-not $allMovedFiles) { Write-Host "No moved files found to remove from source."; return }
    $movedNames = $allMovedFiles | ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Name) } | Select-Object -Unique

    # 2. Find all Function/Class AST nodes that match these names
    $astsToRemove = New-Object System.Collections.Generic.List[System.Management.Automation.Language.Ast]
    foreach ($name in $movedNames) {
        # Find functions
        $astsToRemove.AddRange( ($script:FunctionAsts | Where-Object { $_.Name -ceq $name }) )
        # Find classes
        $astsToRemove.AddRange( ($script:ClassAsts | Where-Object { $_.Name -ceq $name }) )
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
    $newContent | Set-Content -Path $Psm1Path -Encoding UTF8

    Write-Host "Removed $removedCount function/class definition(s) from source. Original backed up at $bak" -ForegroundColor Green
    # 6. Reload the AST since the source has changed
    Load-AstAndSource -Path $Psm1Path
}
function Ensure-OutDirs {
    param([string]$BaseOut)
    $script:PublicDir = Join-Path $BaseOut 'Public'; $script:PrivateDir = Join-Path $BaseOut 'Private'; $script:ClassDir = Join-Path $BaseOut 'Class'
    @($script:PublicDir, $script:PrivateDir, $script:ClassDir) | ForEach-Object { New-Item -Path $_ -ItemType Directory -Force | Out-Null }
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
# ==================================================================
#region * Define Menu Items *
# ==================================================================
$MenuItems = @(
    [PSCustomObject]@{ Id     = '1'; Name = 'Select/Load PSM1 File';                    Enabled = $true
                        Key     = '1'
                        Help    = "Choose the module file to split. Currently loaded: $($script:Psm1Path)"
                        Type    = 'Config'
                        Action  = {
                            $psm1 = Choose-Psm1File -AllowFilesystemSearch
                            if ($psm1) { Load-AstAndSource -Path $psm1 }
                        } }
    [PSCustomObject]@{ Id     = '---'; Name = '------------------------------------'; Enabled = $true; Key = ''; Help = ''; Type = 'Separator'; Action = {} }
   
    # Utility Functions - Require Module Loaded
    [PSCustomObject]@{ Id     = '2'; Name = 'Move Functions (Public/Private/Class)'; Enabled = { Check-ModuleLoaded }
                        Key     = '2'
                        Help    = "Interactively select functions and move them to $script:PublicDir/$script:PrivateDir folders."
                        Type    = 'Utility'
                        Action  = { Interactive-MoveFunctions } }
   
    [PSCustomObject]@{ Id     = '3'; Name = 'Export All Classes';                    Enabled = { Check-ModuleLoaded }
                        Key     = '3'
                        Help    = "Exports all discovered classes to the $script:ClassDir folder immediately."
                        Type    = 'Utility'
                        Action  = { Export-AllClasses } }

    [PSCustomObject]@{ Id     = '4'; Name = 'Write Unused Helper Content';           Enabled = { Check-ModuleLoaded }
                        Key     = '4'
                        Help    = "Extracts code that is not a function or class definition into _helpers.ps1 in $script:PrivateDir."
                        Type    = 'Output'
                        Action  = { Write-Helpers } }

    [PSCustomObject]@{ Id     = '---'; Name = '------------------------------------'; Enabled = { Check-ModuleLoaded }; Key = ''; Help = ''; Type = 'Separator'; Action = {} }

    # Finalization/Cleanup
    [PSCustomObject]@{ Id     = '5'; Name = 'Generate Index/Main PSM1';             Enabled = { Check-ModuleLoaded }
                        Key     = '5'
                        Help    = "Creates the new index .psm1 file that sources all files in the Public/ folder."
                        Type    = 'Output'
                        Action  = { Generate-Index } }
                       
    [PSCustomObject]@{ Id     = '6'; Name = 'Remove Moved from Source (DANGEROUS)'; Enabled = { Check-ModuleLoaded }
                        Key     = '6'
                        Help    = 'BACKS UP source, then removes moved functions/classes from the original PSM1 file.'
                        Type    = 'Cleanup'
                        Action  = { Remove-MovedFromSource } }
   
    [PSCustomObject]@{ Id     = '---'; Name = '------------------------------------'; Enabled = $true; Key = ''; Help = ''; Type = 'Separator'; Action = {} }
   
    [PSCustomObject]@{ Id     = 'Q'; Name = 'Quit Menu';                        Enabled = $true
                        Key     = 'Q'
                        Help    = 'Exit menu'
                        Type    = 'Meta'
                        Action  = { return 'quit' } }
)
#endregion
# ==================================================================
#region * Run Menu *
# ==================================================================
# Explicitly define the desired menu title
$MenuTitleExplicit = "PowerShell Module Splitter Utility"

if (-not [string]::IsNullOrWhiteSpace($MenuTitleExplicit)) {
    $FinalMenuTitle = $MenuTitleExplicit
} else {
    $FinalMenuTitle = Get-MenuTitle
    Write-Verbose "No explicit menu title defined. Falling back to title derived from Get-MenuTitle: '$FinalMenuTitle'."
}

if (Get-Command -Name Show-InteractiveMenu -ErrorAction SilentlyContinue) {
    Show-InteractiveMenu -MenuData $MenuItems -MenuTitle $FinalMenuTitle
} else {
    Write-Error "The Show-InteractiveMenu function was not loaded from InteractiveMenu.psm1. Cannot run menu."
}
#endregion
