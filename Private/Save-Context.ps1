function Save-Context {
    param([psobject]$Context, [string]$Path = (Join-Path $env:TEMP 'menu-context.json'))
    $Context | ConvertTo-Json -Depth 5 | Set-Content -Path $Path -Encoding UTF8
}
