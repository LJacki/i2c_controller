# VCS Makefile for I2C Controller UVM Verification

.PHONY: sim clean

# VCS compilation flags
VCS_FLAGS = -full64 -debug_access+all -lca
VCS_FLAGS += -timescale=1ns/1ps
VCS_FLAGS += -sysv

# UVM options
UVM_HOME ?= /opt/synopsys/vcs/etc/uvm
UVM_FLAGS = +incdir+$(UVM_HOME) -uvm

# Source files
SRC_DIR = ../src
RTL_DIR = ../../rtl
TB_TOP = $(SRC_DIR)/tests/tb_top.sv

# Filelist
FILELIST = filelist.f

# Test name (passed via command line: make sim TEST=test_name)
TEST ?= test_master_single_write

# Top-level module
TOP = tb_top

# VCS Elaboration and simulation
sim:
	@echo "=== Compiling with VCS ==="
	vcs $(VCS_FLAGS) -f $(FILELIST) -top $(TOP) -ntb_opts uvm -l comp.log
	@echo "=== Running simulation ==="
	./simv +UVM_TESTNAME=$(TEST) -l sim.log
	@echo "=== Simulation complete ==="

# Quick compile only (no run)
compile:
	vcs $(VCS_FLAGS) -f $(FILELIST) -top $(TOP) -ntb_opts uvm -l comp.log

clean:
	rm -rf AN.DB csrc DVEfiles *.log *.wlf ucli.key dve.vpd

.PHONY: help
help:
	@echo "Usage:"
	@echo "  make sim TEST=<test_name>   - Compile and run test"
	@echo "  make compile                - Compile only"
	@echo "  make clean                 - Clean generated files"
	@echo ""
	@echo "Available tests:"
	@echo "  test_master_single_write"
	@echo "  test_master_single_read"
	@echo "  test_master_burst_write"
	@echo "  test_slave_receive"
	@echo "  test_slave_transmit"