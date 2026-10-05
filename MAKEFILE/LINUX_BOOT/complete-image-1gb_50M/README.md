# C910 FPGA 1 GiB DDR完整镜像

本目录对应新开发板的1 GiB DDR配置。DDR基址以及所有固件、Linux、initramfs和DTB加载地址均保持原值，仅DDR容量由8 GiB调整为1 GiB。

## DDR范围

```text
DDR base = 0x200000000
DDR size = 0x040000000 (1 GiB)
DDR end  = 0x240000000 (exclusive)
```

## 加载地址

| 对象 | 文件 | 地址 |
| --- | --- | ---: |
| OpenSBI | `opensbi-c910-fpga-fw_jump.bin` | `0x200000000` |
| U-Boot | `u-boot-c910-soc-minimal.bin` | `0x200200000` |
| Linux | `linux-c910-fpga-Image.bin` | `0x200600000` |
| initramfs | `rootfs-c910-lite.cpio.gz` | `0x204000000` |
| 系统DTB | `c910-soc-system-1gb.dtb` | `0x210000000` |

所有加载对象均位于1 GiB DDR范围内。DTB中的`linux,initrd-start/end`由打包脚本根据实际cpio大小自动填写。

## 构建

在工程根目录执行：

```bash
./build-c910-fpga-1gb.sh build
```

仅用已有编译产物重新组包：

```bash
./build-c910-fpga-1gb.sh package
```

## JTAG启动

先下载与新开发板1 GiB DDR颗粒匹配的FPGA bitstream，并确认DDR校准完成。然后在本目录中连接GDB：

```gdb
target remote <JTAG服务器地址:端口>
monitor halt
source load-c910-complete-1gb.gdb
```

U-Boot默认执行：

```text
booti 0x200600000 - 0x210000000
```

## 重要限制

本软件包不会修改或生成Vivado bitstream。新板DDR颗粒、DDR4 IP配置和AXI映射必须在硬件工程中设置为实际1 GiB配置；设备树只能限制软件使用范围，不能修复错误的DDR控制器参数。

当前定时器链路问题仍与原8 GiB镜像相同，需要继续验证CLINT `mtimecmp -> MTIP`链路。
