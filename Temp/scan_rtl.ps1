$ErrorActionPreference = 'Stop'

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$rtlRoot = Join-Path $projectRoot 'gen_rtl'
$outPath = Join-Path $PSScriptRoot 'module_scan.txt'
$files = Get-ChildItem -Path $rtlRoot -Recurse -File -Filter '*.v' | Sort-Object FullName

$definitions = @()
$byName = @{}

foreach ($file in $files) {
    $text = Get-Content -LiteralPath $file.FullName -Raw -Encoding utf8
    foreach ($match in [regex]::Matches($text, '(?im)^[ \t]*module[ \t]+(?<name>[A-Za-z_]\w*)')) {
        $line = ($text.Substring(0, $match.Index) -split "`n").Count
        $relative = $file.FullName.Substring($projectRoot.Length + 1)
        $record = [pscustomobject]@{
            Name = $match.Groups['name'].Value
            File = $relative
            Line = $line
        }
        $definitions += $record
        if (-not $byName.ContainsKey($record.Name)) {
            $byName[$record.Name] = @()
        }
        $byName[$record.Name] += $record
    }
}

$instances = @()
foreach ($file in $files) {
    $text = Get-Content -LiteralPath $file.FullName -Raw -Encoding utf8
    $relative = $file.FullName.Substring($projectRoot.Length + 1)
    $localDefs = @(
        $definitions | Where-Object { $_.File -eq $relative } | Sort-Object Line
    )
    foreach ($match in [regex]::Matches($text, '(?im)^[ \t]*(?<type>[A-Za-z_]\w*)[ \t]*(?:#[ \t]*\([\s\S]*?\)[ \t]*)?(?<inst>[A-Za-z_]\w*)[ \t]*\(')) {
        $type = $match.Groups['type'].Value
        if (-not $byName.ContainsKey($type)) {
            continue
        }
        $line = ($text.Substring(0, $match.Index) -split "`n").Count
        $parent = ($localDefs | Where-Object { $_.Line -le $line } | Select-Object -Last 1).Name
        if ([string]::IsNullOrWhiteSpace($parent)) {
            $parent = '<unknown>'
        }
        $instances += [pscustomobject]@{
            Parent = $parent
            Child = $type
            Instance = $match.Groups['inst'].Value
            File = $relative
            Line = $line
        }
    }
}

$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add("RTL files: $($files.Count)")
$lines.Add("Module definitions: $($definitions.Count)")
$lines.Add('')
$lines.Add('== MODULE DEFINITIONS ==')
foreach ($item in ($definitions | Sort-Object File, Line, Name)) {
    $lines.Add(('{0} | {1}:{2}' -f $item.Name, $item.File, $item.Line))
}
$lines.Add('')
$lines.Add('== MODULE INSTANCES (child type is a defined module) ==')
foreach ($item in ($instances | Sort-Object File, Line, Parent, Child)) {
    $lines.Add(('{0} -> {1} ({2}) | {3}:{4}' -f $item.Parent, $item.Child, $item.Instance, $item.File, $item.Line))
}
$lines.Add('')
$lines.Add('== TOP-LEVEL CANDIDATES BY DEFINITION/INSTANCE COUNTS ==')
$instantiatedNames = @{}
foreach ($item in $instances) {
    if (-not $instantiatedNames.ContainsKey($item.Child)) { $instantiatedNames[$item.Child] = 0 }
    $instantiatedNames[$item.Child]++
}
foreach ($item in ($definitions | Group-Object Name | Sort-Object Name)) {
    $name = $item.Name
    $count = if ($instantiatedNames.ContainsKey($name)) { $instantiatedNames[$name] } else { 0 }
    $filesForName = ($item.Group | ForEach-Object { $_.File }) -join ', '
    $lines.Add(('{0} | instances={1} | files={2}' -f $name, $count, $filesForName))
}

$lines | Set-Content -LiteralPath $outPath -Encoding utf8
Write-Output $outPath
