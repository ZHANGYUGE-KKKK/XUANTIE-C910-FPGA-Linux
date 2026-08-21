# Revido portable package

This package contains the minimum files needed to open the Vivado project outside the original local workspace.

Open:

  VIVADO/C910_SOC/C910_SOC.xpr

Included:

- Vivado project file, source set, block design, constraints and XCI IP configuration files
- Custom IP repository: VIVADO/MY_IP/c910_core_ip_migration
- COE initialization files referenced by the project
- C910_SOC_wrapper.v because the project file references this generated wrapper directly

Excluded:

- Vivado generated/build directories such as .Xil, *.cache, *.hw, *.runs, *.sim and most *.gen outputs
- Local logs/journals
- Local RISC-V toolchain and unrelated MAKEFILE build trees

After opening in Vivado, regenerate IP output products if Vivado requests it.
