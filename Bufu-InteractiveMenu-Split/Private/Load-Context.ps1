function Load-Context {
    param([string]$Path = (Join-Path $env:TEMP 'menu-context.json'))
    if (Test-Path $Path) { return Get-Content $Path -Raw | ConvertFrom-Json } else { return $null }
}
