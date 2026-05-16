# Cocotb Makefile for i2c_ctrl_top with VCS
# i2c_controller / Cocotb Python Verification
#
# Usage:
#   cd /path/to/i2c_controller
#   make -f cocotb/Makefile test

export PATH := /home/xiaoai/.local/bin:$(PATH)

PROJECT     := /home/xiaoai/Desktop/disk1/IC_Project/i2c_controller
RTL_DIR      := $(PROJECT)/rtl
COCOTB_DIR   := $(PROJECT)/cocotb
RESULTS_DIR  := $(PROJECT)/cocotb/results

# ============================================================
# Simulator & design config
# ============================================================
SIM            ?= vcs
TOPLEVEL       := i2c_ctrl_top
MODULE         := cocotb.tests.test_i2c_ctrl
TOPLEVEL_LANG  := verilog

# ============================================================
# RTL Sources (SystemVerilog)
# ============================================================
VERILOG_SOURCES := \
    $(RTL_DIR)/i2c_ctrl_top.sv \
    $(RTL_DIR)/apb_reg_file.sv \
    $(RTL_DIR)/i2c_master_fsm.sv \
    $(RTL_DIR)/i2c_slave_fsm.sv \
    $(RTL_DIR)/i2c_io_buf.v \
    $(RTL_DIR)/rx_fifo.sv \
    $(RTL_DIR)/tx_cmd_fifo.sv \
    $(RTL_DIR)/tx_dat_fifo.v

# ============================================================
# VCS compile options
# ============================================================
VCS_COMPILE_ARGS := -full64 -sverilog -ntb_opts uvm-1.1 \
                    -debug -lca

# ============================================================
# Python path
# ============================================================
export PYTHONPATH := $(COCOTB_DIR):$(RTL_DIR):$(PYTHONPATH)

# ============================================================
# Include cocotb makefile
# ============================================================
include $(shell cocotb-config --makefiles)/sim Makefile.scm

# ============================================================
# Custom targets
# ============================================================
.PHONY: test clean help

test: clean
	@echo "=== Compiling RTL + cocotb VPI for VCS ==="
	cd $(RTL_DIR) && \
	vcs $(VCS_COMPILE_ARGS) \
	    $(VERILOG_SOURCES) \
	    -top $(TOPLEVEL) \
	    -o simv \
	    -loadvpi libcocotbvpi_vcs.so:cocotb_callback_init \
	    -CFLAGS "-I$(shell cocotb-config --share)/include" \
	    -LDFLAGS "-Wl,-rpath,$(shell cocotb-config --lib-dir)" \
	    -DMODULE=$(MODULE) \
	    -DTOPLEVEL=$(TOPLEVEL) \
	    2>&1 | tee $(PROJECT)/cocotb/compile.log
	@echo "=== Running cocotb tests ==="
	cd $(RTL_DIR) && \
	./simv -logfile simv.log $(SIM_ARGS) \
	    2>&1 | tee $(PROJECT)/cocotb/sim.log
	@echo "=== Done ==="

clean:
	cd $(RTL_DIR) && rm -rf simv simv.vdb csrc AN.DB ucli.key compile.log 2>/dev/null
	cd $(RTL_DIR) && rm -f *.log vcs.log 2>/dev/null
	rm -rf $(RESULTS_DIR) 2>/dev/null

help:
	@echo "i2c_ctrl_top cocotb (VCS)"
	@echo "  make -f cocotb/Makefile test"
	@echo "  make -f cocotb/Makefile clean"