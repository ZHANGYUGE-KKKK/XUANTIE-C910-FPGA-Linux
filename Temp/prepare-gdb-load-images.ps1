$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$objcopy = Join-Path $projectRoot 'MAKEFILE\Xuantie-900-gcc-elf-newlib-mingw-V3.2.0\bin\riscv64-unknown-elf-objcopy.exe'
$imageDir = Join-Path $projectRoot 'MAKEFILE\LINUX_BOOT\complete-image-1gb_50M'
$images = @(
    @{ Name = 'opensbi-c910-fpga-fw_jump.bin'; Address = '0x0200000000' },
    @{ Name = 'u-boot-c910-soc-minimal.bin'; Address = '0x0200200000' },
    @{ Name = 'linux-c910-fpga-Image.bin'; Address = '0x0200600000' },
    @{ Name = 'rootfs-c910-lite.cpio.gz'; Address = '0x0204000000' },
    @{ Name = 'c910-soc-system-1gb.dtb'; Address = '0x0210000000' }
)

foreach ($image in $images) {
    $inputFile = Join-Path $imageDir $image.Name
    $outputFile = Join-Path $PSScriptRoot ($image.Name + '.load.elf')
    $checkFile = Join-Path $PSScriptRoot ($image.Name + '.roundtrip.bin')
    & $objcopy -I binary -O elf64-littleriscv -B riscv --change-section-address ('.data=' + $image.Address) --set-start $image.Address $inputFile $outputFile
    if ($LASTEXITCODE -ne 0) { throw "ELF conversion failed: $inputFile" }
    & $objcopy -O binary $outputFile $checkFile
    if ($LASTEXITCODE -ne 0) { throw "Roundtrip conversion failed: $outputFile" }
    if ((Get-FileHash -LiteralPath $inputFile -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $checkFile -Algorithm SHA256).Hash) {
        throw "Roundtrip content mismatch: $inputFile"
    }
    Remove-Item -LiteralPath $checkFile
    Write-Host ("Verified {0} -> {1}, address {2}" -f $image.Name, $outputFile, $image.Address)
}
