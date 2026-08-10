# C910 Core IP 迁移包

本目录是独立 Vivado IP 仓库目录，包含 `user.org:user:c910_core_bd_wrapper:1.0` 的 IP-XACT 描述、RTL 源码和 xgui 脚本。

## 使用方式

在目标 Vivado 工程 Tcl Console 中执行：

```tcl
set_property ip_repo_paths {D:/Xilinx_FPGA/C910_SOC/VIVADO/MY_IP/c910_core_ip_migration} [current_project]
update_ip_catalog
```

然后在 IP Catalog 中搜索：

```text
c910_core_bd_wrapper
```

## 主要接口

- `m_axi`：AXI4 master，128-bit data，40-bit address，8-bit ID
- `aclk`：核心和 AXI 时钟
- `aresetn`：低有效复位
- `jtag_*`：JTAG 调试端口
- `core_retire*`、`core_mstatus`、`cpu_debug_port`、`cpu_no_op`：调试/观测端口

## 主要参数

- `RESET_VECTOR`
- `CPU_APB_BASE`
- `HART_ID`
