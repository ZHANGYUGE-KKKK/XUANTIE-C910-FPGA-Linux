# Static consistency check; no file or project modifications.
$ErrorActionPreference = 'Stop'
$adapterRoot = $PSScriptRoot
$repoRoot = [IO.Path]::GetFullPath((Join-Path $adapterRoot '../../..'))
$socRoot = Join-Path $repoRoot 'VIVADO/C910_SOC'
$pinDoc = Get-Content -Encoding UTF8 -Raw -LiteralPath (Join-Path $adapterRoot 'pinmap.json') | ConvertFrom-Json
$xdcText = Get-Content -Encoding UTF8 -Raw -LiteralPath (Join-Path $socRoot 'C910_SOC.srcs/constrs_1/new/VCU118.xdc')
$wrapperText = Get-Content -Encoding UTF8 -Raw -LiteralPath (Join-Path $socRoot 'C910_SOC.gen/sources_1/bd/C910_SOC/hdl/C910_SOC_wrapper.v')
$officialText = Get-Content -Encoding UTF8 -Raw -LiteralPath (Join-Path $repoRoot 'DATASHEET/VCU118/vcu118-schematic-xtp450_cluster/vcu118-xdc-rdf0400/vcu118_rev2.0_12082017.xdc')

foreach ($field in @('top_port', 'fpga_pin', 'carrier_contact', 'subcard_contact')) {
    if (@($pinDoc.signals.$field | Sort-Object -Unique).Count -ne 50) {
        throw "Missing/duplicate DDR mapping: $field"
    }
}
$wrapperBits = @()
foreach ($decl in [regex]::Matches($wrapperText, '(?m)^\s*(?:input|output|inout)\s+(?:\[(\d+):(\d+)\]\s*)?(C0_DDR3_0_\w+)\s*;')) {
    $name = $decl.Groups[3].Value
    if ($decl.Groups[1].Success) {
        for ($bit = [int]$decl.Groups[2].Value; $bit -le [int]$decl.Groups[1].Value; $bit++) {
            $wrapperBits += ($name + '[' + $bit + ']')
        }
    } else { $wrapperBits += $name }
}
if ($wrapperBits.Count -ne 50) { throw "Expected 50 wrapper DDR bits; found $($wrapperBits.Count)" }
foreach ($row in $pinDoc.signals) {
    if ($row.top_port -notin $wrapperBits) { throw "Not a wrapper port: $($row.top_port)" }
    $binding = 'set_property PACKAGE_PIN ' + $row.fpga_pin + ' [get_ports {' + $row.top_port + '}]'
    if (-not $xdcText.Contains($binding)) { throw "XDC mismatch: $($row.top_port)" }
    $officialPattern = 'set_property PACKAGE_PIN\s+' + [regex]::Escape($row.fpga_pin) + '\s+\[get_ports "' + [regex]::Escape($row.carrier_net) + '"\].*Bank\s+' + $row.bank + '.*' + [regex]::Escape($row.pin_function)
    if (-not [regex]::IsMatch($officialText, $officialPattern)) { throw "Official board XDC mismatch: $($row.top_port)" }
}
foreach ($row in $pinDoc.reference_clock.ports) {
    $baseName = $row.top_port -replace '\[0\]$', ''
    $clockBinding = 'PACKAGE_PIN ' + $row.fpga_pin + ' IOSTANDARD LVDS DIFF_TERM_ADV TERM_NONE} [get_ports ' + $baseName + ']'
    if (-not $xdcText.Contains($clockBinding)) { throw "Reference clock XDC mismatch: $($row.top_port)" }
    $officialPattern = 'set_property PACKAGE_PIN\s+' + [regex]::Escape($row.fpga_pin) + '\s+\[get_ports "' + [regex]::Escape($row.carrier_net) + '"\].*Bank\s+' + $row.bank + '\b'
    if (-not [regex]::IsMatch($officialText, $officialPattern)) { throw "Reference clock official board XDC mismatch: $($row.top_port)" }
}
$ddrAndClockPins = @($pinDoc.signals.fpga_pin) + @($pinDoc.reference_clock.ports.fpga_pin)
if (@($ddrAndClockPins | Sort-Object -Unique).Count -ne 52) { throw 'Clock/DDR pin collision' }
$ddrAndClockContacts = @($pinDoc.signals.carrier_contact) + @($pinDoc.reference_clock.ports.carrier_contact)
if (@($ddrAndClockContacts | Sort-Object -Unique).Count -ne 52) { throw 'Clock/DDR carrier connector contact collision' }
foreach ($otherPin in @('L19', 'AW25', 'BB21', 'P11', 'R11', 'N15', 'P15', 'AG33')) {
    if ($otherPin -in $ddrAndClockPins) { throw "Non-DDR collision: $otherPin" }
}
Write-Output 'PASS: 50 DDR mappings match wrapper, XDC, and official VCU118 net/bank/pin functions.'
Write-Output 'PASS: 52 unique DDR/reference-clock FPGA pins; no UART/reset/JTAG pin collisions.'
Write-Output 'PASS: 52 unique J2 signal contacts; reference-clock net/bank/pins match official VCU118 XDC.'
Write-Output 'NOTE: This is a static check, not a Vivado physical DRC or a hardware voltage/SI test.'
