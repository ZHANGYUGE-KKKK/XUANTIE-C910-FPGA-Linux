THIS_MAKEFILE := $(lastword $(MAKEFILE_LIST))
JTAG_DIR := $(patsubst %/,%,$(dir $(THIS_MAKEFILE)))
CASE_DIR := $(JTAG_DIR)/..
WORKLOAD ?= all
CPU_HZ ?= 100000000
ITERATIONS ?= 1
RUNS ?= 3
MIN_SECONDS ?= 1

.PHONY: all check clean
all:
	@powershell -NoProfile -ExecutionPolicy Bypass -File "$(CASE_DIR)/build.ps1" -Workload "$(WORKLOAD)" -CpuHz $(CPU_HZ) -Iterations $(ITERATIONS) -Runs $(RUNS) -MinSeconds $(MIN_SECONDS)
check:
	@powershell -NoProfile -ExecutionPolicy Bypass -File "$(CASE_DIR)/build.ps1" -Workload "$(WORKLOAD)" -CheckOnly
clean:
	@powershell -NoProfile -ExecutionPolicy Bypass -File "$(CASE_DIR)/build.ps1" -Clean
