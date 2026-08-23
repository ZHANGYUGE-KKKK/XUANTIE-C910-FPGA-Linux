# C910 FPGA 完整镜像

## 地址规划

| 阶段 | 文件 | 加载地址 |
| --- | --- | --- |
| OpenSBI | `opensbi-c910-fpga-fw_jump.bin` | `0x200000000` |
| U-Boot | `u-boot-c910-soc-minimal.bin` | `0x200200000` |
| Linux | `linux-c910-fpga-Image.bin` | `0x200600000` |
| initramfs | `rootfs-c910-lite.cpio.gz` | `0x204000000` |
| 系统 DTB | `c910-soc-system.dtb` | `0x210000000` |

`c910-soc-system.dtb` 中的 `linux,initrd-start/end` 已按照同目录
`rootfs-c910-lite.cpio.gz` 的实际大小生成。不要只替换 rootfs 而不重新运行
`build-c910-fpga-complete.sh package`。

## JTAG 启动

先连接并停止 CPU，然后把 GDB 当前目录切换到 `complete-image`，执行：

```gdb
source load-c910-complete.gdb
```

等价的核心命令是：

```gdb
restore opensbi-c910-fpga-fw_jump.bin binary 0x200000000
restore u-boot-c910-soc-minimal.bin binary 0x200200000
restore linux-c910-fpga-Image.bin binary 0x200600000
restore rootfs-c910-lite.cpio.gz binary 0x204000000
restore c910-soc-system.dtb binary 0x210000000
set $a0 = 0
set $a1 = 0x210000000
set $pc = 0x200000000
continue
```

U-Boot 默认执行：

```text
booti 0x200600000 - 0x210000000
```

initramfs 地址来自 DTB，因此不需要额外输入 ramdisk 参数，也不再加载 U-Boot
separate DTB。

## 根文件系统

JTAG 启动使用 `rootfs-c910-lite.cpio.gz`。它包含 `/init`、BusyBox、SSH 和
`hvc0` getty，Linux 控制台参数为 `console=hvc0 earlycon=sbi`。

`rootfs-c910-lite.ext4` 是内容相同的可写 ext4 根文件系统，供以后接入 SD、
eMMC、NVMe 或其他块设备时烧录使用；当前 JTAG initramfs 流程不加载该文件。

使用下面的命令检查文件完整性：

```bash
sha256sum -c SHA256SUMS
```

## 重新构建

```bash
./build-c910-fpga-complete.sh build
```

只重新收集已有 Yocto 产物并更新 DTB initramfs 地址：

```bash
./build-c910-fpga-complete.sh package
```
