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
if (@($pinDoc.reference_clock.ports | Where-Object { $null -ne $_.carrier_contact }).Count -ne 0) {
    throw 'Reference clock must not be connected to the adapter FMC contacts'
}
$bdDoc = Get-Content -Encoding UTF8 -Raw -LiteralPath (Join-Path $socRoot 'C910_SOC.srcs/sources_1/bd/C910_SOC/C910_SOC.bd') | ConvertFrom-Json
$clockSinkNet = @($bdDoc.design.nets.PSObject.Properties | Where-Object { 'DDR3/c0_sys_clk_i' -in $_.Value.ports })
if ($clockSinkNet.Count -ne 1 -or 'board_sysclk_bufg_0/clk_out' -notin $clockSinkNet[0].Value.ports -or 'clk_wiz/clk_in1' -notin $clockSinkNet[0].Value.ports) {
    throw 'MIG and clk_wiz must be driven by board_sysclk_bufg_0'
}
$clockSourceNet = @($bdDoc.design.nets.PSObject.Properties | Where-Object { 'board_sysclk_bufg_0/clk_in' -in $_.Value.ports })
if ($clockSourceNet.Count -ne 1 -or 'util_ds_buf_0/IBUF_OUT' -notin $clockSourceNet[0].Value.ports) {
    throw 'Reference BUFG must be fed by the board differential IBUFDS'
}
if ($bdDoc.design.components.DDR3.parameters.'C0.DDR3_InputClockPeriod'.value -ne '4000') {
    throw 'MIG reference frequency must remain 250 MHz / 4000 ps'
}
if (-not $xdcText.Contains('set_property LOC BUFGCE_X1Y120') -or -not $xdcText.Contains('set_property CLOCK_DEDICATED_ROUTE BACKBONE')) {
    throw 'Missing dedicated cross-bank clock placement/routing constraints'
}
foreach ($otherPin in @('L19', 'AW25', 'BB21', 'P11', 'R11', 'N15', 'P15', 'AG33')) {
    if ($otherPin -in $ddrAndClockPins) { throw "Non-DDR collision: $otherPin" }
}
# Independently verify every generated contact and the original carrier GND symbol.
$groundSymbol = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'DATASHEET/VCU118/vcu118-schematic-xtp450_cluster/vcu118-schematic-source-rdf0398/Libs/GOLDEN_SYMBOLS/sym/asp_134486_01_gnd.1')
$officialGround = @([regex]::Matches($groundSymbol, '#=([ABCDEFGHJK]\d{1,2})\b') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
$declaredGround = @($pinDoc.ground_contacts.standard_carrier_ground_by_row.PSObject.Properties | ForEach-Object {
    $rowName = $_.Name
    $_.Value | ForEach-Object { $rowName + $_ }
} | Sort-Object -Unique)
if ($officialGround.Count -ne 159 -or @(Compare-Object $officialGround $declaredGround).Count -ne 0) {
    throw 'Standard carrier ground contacts do not match original connector symbol'
}
$manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $adapterRoot 'output/adapter_netlist.json') | ConvertFrom-Json
if ($manifest.source_sha256 -ne (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $adapterRoot 'pinmap.json')).Hash.ToLower()) {
    throw 'Generated documentation/netlist is stale: regenerate after changing pinmap.json'
}
$expected = @{J1=@{};J2=@{}}
foreach ($pin in @($declaredGround) + @($pinDoc.ground_contacts.carrier_add_to_ground)) { $expected.J1[$pin] = 'GND' }
foreach ($pin in @($declaredGround | Where-Object { $_ -notin $pinDoc.ground_contacts.subcard_remove_from_standard_ground }) + @($pinDoc.ground_contacts.subcard_add_to_ground)) { $expected.J2[$pin] = 'GND' }
foreach ($power in $pinDoc.power_connections) {
    foreach ($pin in $power.carrier_contacts) { $expected.J1[$pin] = $power.net }
    foreach ($pin in $power.subcard_contacts) { $expected.J2[$pin] = $power.net }
}
foreach ($signal in $pinDoc.signals) {
    $net = $signal.top_port -replace '^C0_DDR3_0_', ''
    $net = $net -replace '^addr\[(\d+)\]$', 'A$1' -replace '^ba\[(\d+)\]$', 'BA$1' -replace '^dq\[(\d+)\]$', 'DQ$1' -replace '^dm\[(\d+)\]$', 'DM$1'
    $net = $net -replace '^dqs_([pn])\[(\d+)\]$', 'DQS$2_$1' -replace '^ck_([pn])\[0\]$', 'CK_$1' -replace '\[0\]$', ''
    $net = 'DDR_' + $net.ToUpperInvariant()
    foreach ($pair in @(@('J1',$signal.carrier_contact),@('J2',$signal.subcard_contact))) {
        if ($expected[$pair[0]].ContainsKey($pair[1])) { throw "Signal/power/ground collision at $($pair -join '.')" }
        $expected[$pair[0]][$pair[1]] = $net
    }
}
if ($manifest.contact_count -ne 800 -or @($manifest.nets.PSObject.Properties).Count -ne 53) { throw 'Incomplete full-contact netlist' }
foreach ($ref in @('J1','J2')) {
    if (@($manifest.contacts.$ref.PSObject.Properties).Count -ne 400) { throw "Incomplete connector $ref" }
    foreach ($letter in 'ABCDEFGHJK'.ToCharArray()) {
        foreach ($number in 1..40) {
            $pin = [string]$letter + $number
            $item = $manifest.contacts.$ref.$pin
            $target = $expected[$ref][$pin]
            if ($null -eq $item -or $item.net -cne $target) { throw "Full-contact net mismatch at $ref.$pin" }
            if ($null -eq $target) {
                if ($item.status -ne 'NC') { throw "Unlisted contact not NC: $ref.$pin" }
            } else {
                $nodes = @($manifest.nets.$target | Where-Object { $_.ref -eq $ref -and $_.pin -eq $pin })
                if ($nodes.Count -ne 1) { throw "Net node mismatch at $ref.$pin" }
            }
        }
    }
}
foreach ($ref in @('J1','J2')) {
    foreach ($pin in @('C35','C37','D1')) {
        if ($null -ne $manifest.contacts.$ref.$pin.net) { throw "Unsafe forbidden connection: $ref.$pin" }
    }
}
if ($manifest.contacts.J1.G6.status -ne 'NC' -or $manifest.contacts.J1.G7.status -ne 'NC') { throw 'FMC reference clock must remain disconnected' }
foreach ($pin in @('B2','F2','H2')) {
    if ($manifest.contacts.J2.$pin.net -ne 'GND') { throw "Source-confirmed daughter ground missing: $pin" }
}
foreach ($pin in @('G17','G26','H6')) {
    if ($manifest.contacts.J2.$pin.status -ne 'NC') { throw "Source-confirmed daughter NC incorrectly connected: $pin" }
}
if ($manifest.statistics.J1.GND -ne 162 -or $manifest.statistics.J2.GND -ne 157 -or
    $manifest.statistics.J1.NC -ne 179 -or $manifest.statistics.J2.NC -ne 184) { throw 'Incorrect reviewed contact counts' }
Write-Output 'PASS: 50 DDR mappings match wrapper, XDC, and official VCU118 net/bank/pin functions.'
Write-Output 'PASS: 52 unique DDR/reference-clock FPGA pins; no UART/reset/JTAG pin collisions.'
Write-Output 'PASS: 50 DDR J2 contacts; reference clock uses onboard AW23/AW22, not FMC.'
Write-Output 'PASS: BD IBUFDS -> BUFG -> MIG/clk_wiz; MIG 250 MHz unchanged; dedicated BACKBONE constraints present.'
Write-Output 'PASS: Original 159 carrier ground contacts match; full 800-contact / 53-net documentation is current and consistent.'
Write-Output 'PASS: All unlisted contacts NC; 12V/PGOOD and old FMC reference contacts isolated.'
Write-Output 'PASS: Revision C daughter GND/NC corrections enforced (B2/F2 GND; G17/G26/H6 NC).'
Write-Output 'NOTE: This is a static check, not a Vivado physical DRC or a hardware voltage/SI test.'
