param(
    [Parameter(Mandatory=$true)][string[]]$Logs,
    [ValidateRange(1,100)][int]$ExpectedRuns = 3
)
$ErrorActionPreference = 'Stop'
$culture = [Globalization.CultureInfo]::InvariantCulture
# Reference rates copied from upstream util/perl/cert_mark.pl.
$references = [ordered]@{
    'cjpeg-rose7-preset'=40.3438; 'core'=0.2855;
    'linear_alg-mid-100x100-sp'=38.5624; 'loops-all-mid-10k-sp'=0.87959;
    'nnet_test'=1.45853; 'parser-125k'=4.81116; 'radix2-big-64k'=99.6587;
    'sha-test'=48.5201; 'zip-test'=21.3618
}
$sessions = @{}
$active = $null
$commonCpu = $null
$commonBuild = $null
$commonConfig = $null
$suite = $null
foreach ($pattern in $Logs) {
    $files = @(Get-ChildItem -Path $pattern -File)
    if (-not $files.Count) { throw "No log files match: $pattern" }
    foreach ($file in $files) {
        $active = $null
        foreach ($raw in Get-Content -LiteralPath $file.FullName) {
            $line = $raw.Trim()
            if ($line.StartsWith('COREMARK_PRO_SUITE_')) {
                if ($line -match '^COREMARK_PRO_SUITE_BEGIN workloads=(\d+)$') {
                    if ($suite -or $sessions.Count) { throw 'Multiple suites or mixed suite/standalone logs' }
                    if ([int]$Matches[1] -ne $references.Count) { throw "Invalid suite workload count: $line" }
                    $suite = @{file=$file.FullName;done=$false}
                } elseif ($line -match '^COREMARK_PRO_SUITE_DONE workloads=(\d+) passed=(\d+) failed=(\d+)$') {
                    if (-not $suite -or $suite.done -or $suite.file -ne $file.FullName) {
                        throw 'Suite completion without a matching begin marker'
                    }
                    if ([int]$Matches[1] -ne $references.Count -or [int]$Matches[2] -ne $references.Count -or
                        [int]$Matches[3] -ne 0 -or $sessions.Count -ne $references.Count) {
                        throw "Incomplete or failed suite: $line"
                    }
                    foreach ($session in $sessions.Values) {
                        if (-not $session.done) { throw "Suite completed before workload: $($session.name)" }
                    }
                    $suite.done = $true
                    $active = $null
                } else {
                    throw "Failed or invalid suite marker: $line"
                }
                continue
            }
            if ($line -match '^COREMARK_PRO_BEGIN workload=(\S+) cpu_hz=(\d+) hart=0 contexts=1$') {
                if ($suite -and $suite.done) { throw 'Workload after completed suite' }
                if ($active -and -not $active.done) { throw 'Incomplete previous session' }
                $name = $Matches[1]; $cpu = [double]::Parse($Matches[2],$culture)
                if (-not $references.Contains($name) -or $cpu -le 0) { throw "Invalid session: $line" }
                if ($sessions.ContainsKey($name)) { throw "Duplicate workload session: $name" }
                if ($null -ne $commonCpu -and $cpu -ne $commonCpu) { throw 'Mixed CPU frequencies' }
                $commonCpu = $cpu
                $active = @{name=$name;cpu=$cpu;rates=@{};validated=$false;post=$false;done=$false;build=$false;config=$false;measure=$false}
                $sessions[$name] = $active
                continue
            }
            if ($line -match '^COREMARK_PRO_(FAILED|TRAP)|^RESULT_ERROR') { throw "Benchmark failed: $line" }
            if (-not $active) { continue }
            if ($line.StartsWith('BUILD ')) {
                if ($commonBuild -and $commonBuild -ne $line) { throw 'Mixed compiler flags or upstream revisions' }
                $commonBuild = $line; $active.build = $true
            } elseif ($line.StartsWith('CONFIG ')) {
                if ($commonConfig -and $commonConfig -ne $line) { throw 'Mixed CPU/cache register settings' }
                $commonConfig = $line; $active.config = $true
            } elseif ($line -match '^MEASURE runs=(\d+) min_seconds=(\d+) timer=mcycle units=cycles$') {
                if ([int]$Matches[1] -ne $ExpectedRuns -or [int]$Matches[2] -lt 1) {
                    throw 'Use the expected run count and at least one second for scored runs'
                }
                $active.minimum = [int]$Matches[2]; $active.measure = $true
            } elseif ($line -eq "VALIDATION_PASS workload=$($active.name)") {
                $active.validated = $true
            } elseif ($line.StartsWith('RESULT,')) {
                $fields = $line.Split(',')
                if ($fields.Count -ne 10 -or $fields[1] -ne $active.name -or $fields[9] -ne 'PASS' -or
                    -not $active.validated -or -not $active.measure -or $active.post -or $active.done) {
                    throw "Invalid result sequence: $line"
                }
                $run = [int]$fields[2]; $iterations = [uint64]$fields[3]
                $cycles = [uint64]$fields[4]; $instructions = [uint64]$fields[5]
                if ($run -lt 1 -or $run -gt $ExpectedRuns -or $active.rates.ContainsKey($run) -or
                    -not $iterations -or -not $instructions -or $cycles -lt $active.cpu * $active.minimum) {
                    throw "Invalid or too-short measurement: $line"
                }
                $active.rates[$run] = [double]$iterations * $active.cpu / $cycles
            } elseif ($line -eq "POST_VALIDATION_PASS workload=$($active.name)") {
                if ($active.rates.Count -ne $ExpectedRuns) { throw 'Post-validation arrived before all results' }
                $active.post = $true
            } elseif ($line -eq 'COREMARK_PRO_DONE code=0x0000000000000000') {
                if (-not $active.post -or -not $active.build -or -not $active.config) { throw 'Missing validation or metadata' }
                $active.done = $true
            }
        }
        if ($active -and -not $active.done) { throw "Incomplete log: $($file.FullName)" }
        if ($suite -and $suite.file -eq $file.FullName -and -not $suite.done) {
            throw "Missing successful suite completion marker: $($file.FullName)"
        }
    }
}
$logSum = 0.0
foreach ($name in $references.Keys) {
    if (-not $sessions.ContainsKey($name) -or -not $sessions[$name].done) { throw "Missing complete workload: $name" }
    $rates = @($sessions[$name].rates.Values | Sort-Object)
    $median = $rates[[int][Math]::Floor($ExpectedRuns / 2)]
    if ($ExpectedRuns % 2 -eq 0) { $median = ($median + $rates[$ExpectedRuns / 2 - 1]) / 2 }
    $logSum += [Math]::Log($median / $references[$name])
    Write-Output ('{0},median_iter_per_sec={1}' -f $name,$median.ToString('F9',$culture))
}
$score = 1000 * [Math]::Exp($logSum / $references.Count)
Write-Output ('COREMARK_PRO_RESEARCH_SCORE={0} contexts=1 workloads=9 runs={1} cpu_hz={2}' -f $score.ToString('F6',$culture),$ExpectedRuns,$commonCpu)
