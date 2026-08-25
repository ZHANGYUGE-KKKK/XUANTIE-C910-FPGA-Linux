# C910 OpenSBI 定时器调试镜像

本目录是独立的 OpenSBI 定时器调试产物，不会覆盖
`FPGA配置/complete-image` 中的正常版 OpenSBI。调试版仍然保留 C910
`MXSTATUS[21]`/`SXSTATUS[21]` MAEE 清除逻辑。

## 构建

```bash
cd /home/lhb/linux/c910
./build-c910-timer-debug-opensbi.sh
```

## JTAG 加载

连接 JTAG 并停止 CPU 后，在 GDB 中执行：

```gdb
cd /home/lhb/linux/c910/FPGA配置/timer-debug-image
source load-c910-timer-debug.gdb
```

该脚本从当前目录加载定时器调试版 OpenSBI，U-Boot、Linux、
initramfs 和 DTB 则从 `../complete-image` 加载，地址规划不变。

## 日志含义

```text
[TIMER] smode_event_start ...
```

表示 Linux 已通过 SBI TIME set_timer 进入 OpenSBI。

```text
[TIMER] mtimer_event_start ...
[TIMER] mtimer_event_written ...
```

表示 MTIMER device 已注册，OpenSBI 已读取当前 `time` 并写入该 hart
对应的 `mtimecmp`。`mtimer_event_written` 使用两次 32 位 MMIO 读取，
分别输出 `cmp_lo` 和 `cmp_hi`，与 `next_event` 的低 32 位和高 32 位对照。

```text
[TIMER] sbi_timer_process ...
```

表示 compare 到期后 OpenSBI 收到了 M_TIMER 中断。

该镜像会在每次 timer 设置和中断时通过 UARTLite 打印，不适合作为
长期运行镜像。完成定位后应恢复使用 `complete-image` 中的正常版。
