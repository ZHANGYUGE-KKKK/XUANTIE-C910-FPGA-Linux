# Linux Boot 地址规划

## 1. 当前固定硬件地址

| 模块 | 地址/范围 |
| --- | --- |
| BootROM | `0x00000000`，4KB |
| BRAM | `0x00010000`，64KB |
| UART Lite | `0x40000000`，4KB |
| DDR4 | `0x0200000000`，8GB |

## 2. DDR 镜像规划

| 镜像 | 地址 | 当前用途 |
| --- | --- | --- |
| OpenSBI `fw_jump` | `0x0200000000` | BRAM stub 跳转入口 |
| U-Boot | `0x0200200000` | OpenSBI 下一阶段入口，2.5 再验证 |
| Linux Image | `0x0204000000` | 2.6 再验证 |
| DTB | `0x0210000000` | BRAM stub 通过 `a1` 传给 OpenSBI |
| initramfs | `0x0220000000` | 可选，后续使用 |

## 3. 当前 2.3 验证范围

当前只验证：

```text
BRAM stub -> OpenSBI
```

OpenSBI 使用 `fw_jump` 形态构建，但 2.3 阶段不要求 U-Boot 已经存在。

因此看到 OpenSBI banner 即表示 2.3 的最小启动验证通过。

