param(
    [string]$Workload = 'all',
    [ValidateRange(1,2147483647)][long]$CpuHz = 150000000,
    [ValidateRange(1,2147483647)][long]$Iterations = 1,
    [ValidateRange(1,100)][int]$Runs = 5,
    [ValidateRange(0,3600)][int]$MinSeconds = 1,
    [switch]$CheckOnly,
    [switch]$Clean
)
$ErrorActionPreference = 'Stop'
$caseRoot = $PSScriptRoot.Replace('\','/')
$vendor = "$caseRoot/vendor/coremark-pro-main"
$build = "$caseRoot/JTAG/build"
$toolsRoot = (Resolve-Path "$caseRoot/../Xuantie-900-gcc-elf-newlib-mingw-V3.2.0/bin").Path.Replace('\','/')
$cc = "$toolsRoot/riscv64-unknown-elf-gcc.exe"
$objcopy = "$toolsRoot/riscv64-unknown-elf-objcopy.exe"
$objdump = "$toolsRoot/riscv64-unknown-elf-objdump.exe"
$readelf = "$toolsRoot/riscv64-unknown-elf-readelf.exe"
$sizeTool = "$toolsRoot/riscv64-unknown-elf-size.exe"
if ($Clean) {
    $resolvedBuild = [IO.Path]::GetFullPath($build)
    $expectedRoot = [IO.Path]::GetFullPath($caseRoot) + [IO.Path]::DirectorySeparatorChar
    if (-not $resolvedBuild.StartsWith($expectedRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe build path' }
    if (Test-Path -LiteralPath $resolvedBuild) { Remove-Item -LiteralPath $resolvedBuild -Recurse -Force }
    exit 0
}
& "$caseRoot/verify-upstream.ps1"
if (-not $?) { throw 'Upstream integrity check failed' }
# Source lists and dataset selections follow the upstream kernel Makefiles.
$configs = @(
    @{ Name='cjpeg-rose7-preset'; Kernel='consumer_v2/cjpeg'; Defines=@('USE_PRESET=1','SELECT_PRESET_ID=1');
       Files=@('bmark_lite','bm_lib','cdjpeg','cjpeg','filedata','jcapimin','jcapistd','jccoefct','jccolor','jcdctmgr','jchuff','jcinit','jcmainct','jcmarker','jcmaster','jcomapi','jcparam','jcprepct','jcsample','jdatadst','jerror','jfdctint','jmemansi','jmemmgr','jutils','rdbmp','data/Rose256_bmp','data/goose_bmp') },
    @{ Name='core'; Kernel='core'; Defines=@('USE_CRC_TABLE=1'); Files=@('core_mith','core_matrix','core_list_join','core_state','core_util','core_portme') },
    @{ Name='linear_alg-mid-100x100-sp'; Kernel='fp/linpack'; Defines=@('USE_FP32=1','SP=1'); Files=@('linpack','ref/inputs_f32') },
    @{ Name='loops-all-mid-10k-sp'; Kernel='fp/loops'; Defines=@('USE_FP32=1'); Files=@('loops','ref-sp/1k','ref-sp/10k','ref-sp/100k','ref-sp/1kdot','ref-sp/10kdot','ref-sp/100kdot','ref-sp/100','ref-sp/32') },
    @{ Name='nnet_test'; Kernel='fp/nnet'; Defines=@('USE_FP64=1'); Files=@('nnet','ref/letters','ref/1letter') },
    @{ Name='parser-125k'; Kernel='darkmark/parser'; Defines=@('EZXML_NOMMAP=1'); Files=@('parser','ezxml') },
    @{ Name='radix2-big-64k'; Kernel='fp/fft_radix2'; Defines=@('USE_FP64=1'); Files=@('fft_radix2','ref/2K','ref/32K','ref/4K','ref/data3_big','ref/data4_mid','ref/data5_small') },
    @{ Name='sha-test'; Kernel='darkmark/sha'; Defines=@(); Files=@('sha256','shabench') },
    @{ Name='zip-test'; Kernel='darkmark/zip'; Defines=@('MITH_MEMORY_ONLY_VERSION=1','ZLIB_COMPAT_ALL','ZLIB_ANSI');
       Files=@('zip_darkmark','zlib-1.2.8/adler32','zlib-1.2.8/crc32','zlib-1.2.8/deflate','zlib-1.2.8/infback','zlib-1.2.8/inffast','zlib-1.2.8/inflate','zlib-1.2.8/inftrees','zlib-1.2.8/trees','zlib-1.2.8/zutil','zlib-1.2.8/compress','zlib-1.2.8/uncompr','zlib-1.2.8/gzclose','zlib-1.2.8/gzlib') }
)
if ($Workload -ne 'all') {
    $configs = @($configs | Where-Object { $_.Name -eq $Workload })
    if ($configs.Count -eq 0) { throw "Unknown workload: $Workload" }
}
$compilerFlags = @('-march=rv64imafdc_zicsr_zifencei','-mabi=lp64d','-mcmodel=medany','-msmall-data-limit=0',
    '-O2','-g','-std=gnu99','-ffunction-sections','-fdata-sections','-fno-common','-fno-strict-aliasing',
    '-Wno-error=implicit-function-declaration','-Wno-error=incompatible-pointer-types')
$defines = @('HOST_EXAMPLE_CODE=0','USE_SINGLE_CONTEXT=1','SINGLE_CONTEXT=1','HAVE_PTHREAD=0','USE_NATIVE_PTHREAD=0',
    'EE_SIZEOF_LONG=8','EE_SIZEOF_PTR=8','EE_PTR_ALIGN=8','FAKE_FILEIO=1',
    'HAVE_GETPID=0','HAVE_DIRENT_H=0','HAVE_UNISTD_H=0','HAVE_SYS_STAT_H=1','GCC_INLINE_MACRO=1',
    'NO_RESTRICT_QUALIFIER=1','USE_TH_PRINTF=0','NDEBUG')
$includes = @("$caseRoot/port","$vendor/mith/include","$vendor/mith/al/include")
$harness = @(Get-ChildItem "$vendor/mith/src/*.c" | Sort-Object Name | ForEach-Object { $_.FullName.Replace('\','/') })
$harness += @("$vendor/mith/al/src/al_single.c","$vendor/mith/al/src/al_smp.c","$vendor/mith/al/src/al_file.c")
$localSources = @('start.S','board.c','syscalls.c','th_al.c','fp_port.c','main.c') | ForEach-Object { "$caseRoot/port/$_" }
function Invoke-Tool([string]$exe, [string[]]$toolArgs) {
    & $exe @toolArgs
    if ($LASTEXITCODE -ne 0) { throw "$([IO.Path]::GetFileName($exe)) failed ($LASTEXITCODE)" }
}
function Write-Ascii([string]$path, [string]$content) { [IO.File]::WriteAllText($path,$content,[Text.Encoding]::ASCII) }
$manifest = @()
foreach ($config in $configs) {
    $name = $config.Name
    $out = "$build/$name"
    $elf = "$out/$name.elf"
    if (-not $CheckOnly) {
        New-Item -ItemType Directory -Force "$out/obj" | Out-Null
        $flagString = $compilerFlags -join ' '
        Write-Ascii "$out/build_config.h" @"
#include <stdio.h>
#define FILE_TYPE_DEFINED
#define BENCH_CPU_HZ ${CpuHz}UL
#define BENCH_ITERATIONS ${Iterations}U
#define BENCH_RUNS ${Runs}U
#define BENCH_MIN_SECONDS ${MinSeconds}U
#define BENCH_WORKLOAD "$name"
#define BENCH_FLAGS "$flagString"
#define BENCH_UPSTREAM "4832cc67b0926c7a80a4b7ce0ce00f4640ea6bec"
"@
        $inc = @($includes + @("$vendor/benchmarks/$($config.Kernel)","$vendor/benchmarks/consumer_v2/common",
            "$vendor/benchmarks/consumer_v2/cjpeg/data","$vendor/benchmarks/darkmark/zip/zlib-1.2.8")) | ForEach-Object { "-I$_" }
        $defs = @($defines + $config.Defines) | ForEach-Object { "-D$_" }
        $commonArgs = @($compilerFlags + $defs + $inc + @('-include',"$out/build_config.h"))
        $sources = @($localSources + $harness)
        $sources += @($config.Files | ForEach-Object { "$vendor/benchmarks/$($config.Kernel)/$_.c" })
        $workloadSource = "$vendor/workloads/$name/$name.c"
        $sources += $workloadSource
        $objects = @()
        Write-Host "Building CoreMark-PRO: $name"
        for ($i=0; $i -lt $sources.Count; ++$i) {
            $source = $sources[$i]
            $obj = "$out/obj/$i.o"
            $argsForSource = @($commonArgs)
            if ($source -eq $workloadSource) { $argsForSource += '-Dmain=coremark_workload_main' }
            if ($source.EndsWith('.S')) { $argsForSource = @($compilerFlags) }
            $argsForSource += @('-c',$source,'-o',$obj)
            # A response file avoids cmd.exe limits and preserves workspace paths with spaces.
            $rsp = "$out/compile.rsp"
            Write-Ascii $rsp (($argsForSource | ForEach-Object { '"' + $_ + '"' }) -join "`n")
            Invoke-Tool $cc @("@$rsp")
            $objects += $obj
        }
        $linkArgs = @($compilerFlags + @('-nostartfiles','-Wl,--gc-sections','-Wl,--wrap=mith_main',
            "-Wl,-T,$caseRoot/JTAG/ddr.ld", "-Wl,-Map,$out/$name.map") + $objects + @('-Wl,--start-group','-lc','-lm','-lgcc','-Wl,--end-group','-o',$elf))
        Write-Ascii "$out/link.rsp" (($linkArgs | ForEach-Object { '"' + $_ + '"' }) -join "`n")
        Invoke-Tool $cc @("@$out/link.rsp")
        Invoke-Tool $objcopy @('-O','binary',$elf,"$out/$name.bin")
        $dump = & $objdump -d -h $elf
        if ($LASTEXITCODE -ne 0) { throw 'objdump failed' }
        [IO.File]::WriteAllLines("$out/$name.dump",[string[]]$dump,[Text.Encoding]::ASCII)
        # Set symbols/entry explicitly; never depend on the old stub's ebreak address.
        Write-Ascii "$out/load.gdb" @"
set confirm off
file "$elf"
load "$elf"
set `$pc = _start
printf "CoreMark-PRO $name loaded. Starting bare-metal DDR workload.\n"
continue
"@
        $summary = [ordered]@{ workload=$name; cpu_hz=$CpuHz; initial_iterations=$Iterations; runs=$Runs;
            min_seconds=$MinSeconds; compiler_flags=$flagString; defines=$defines+$config.Defines; sources=$sources }
        $summary | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 "$out/build.json"
    }
    if (-not (Test-Path -LiteralPath $elf)) { throw "Missing ELF: $elf" }
    $headers = & $readelf -h -l $elf
    if ($LASTEXITCODE -ne 0) { throw 'readelf failed' }
    $headerText = $headers -join "`n"
    if ($headerText -notmatch 'Entry point address:\s+0x200000000') { throw "Wrong DDR entry: $name" }
    if ($headerText -notmatch 'Machine:\s+RISC-V') { throw "Wrong ELF machine: $name" }
    Invoke-Tool $sizeTool @($elf)
    $stream = [IO.File]::OpenRead($elf)
    $hasher = [Security.Cryptography.SHA256]::Create()
    try { $digest = [BitConverter]::ToString($hasher.ComputeHash($stream)).Replace('-','') }
    finally { $stream.Dispose(); $hasher.Dispose() }
    $manifest += [pscustomobject]@{ workload=$name; elf=$elf; sha256=$digest }
    Write-Host "PASS: $name (entry 0x200000000; linker checked DDR/heap/stack bounds)"
}
if (-not $CheckOnly) { $manifest | Export-Csv -NoTypeInformation -Encoding UTF8 "$build/images.csv" }
