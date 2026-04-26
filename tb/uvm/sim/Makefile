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
TB_TOP = $(SRC_DIR)/tests/tb_top.sv

# Filelist
FILELIST = filelist.f

# Test name (passed via command line: make sim TEST=test_name)
TEST ?= test_basic_master_single_write

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
	@echo "=== Basic Directed Tests (basic/) ==="
	@echo "  test_basic_master_single_write     - Single byte write"
	@echo "  test_basic_master_burst_write      - Burst write (8 bytes)"
	@echo "  test_basic_master_single_read      - Single byte read"
	@echo "  test_basic_master_burst_read       - Burst read (8 bytes)"
	@echo "  test_basic_master_repeated_start   - Write then Read (Repeated START)"
	@echo "  test_basic_master_addr_nack        - Address NACK, TX_ABRT detection"
	@echo "  test_basic_master_data_nack        - Data NACK, TX_ABRT detection"
	@echo "  test_basic_slave_receive           - Slave receives data"
	@echo "  test_basic_slave_transmit          - Slave transmits data"
	@echo "  test_basic_slave_addr_no_match     - Address mismatch, slave silent"
	@echo ""
	@echo "=== Interrupt Tests (interrupt/) ==="
	@echo "  test_interrupt_rx_full             - RX_FULL interrupt"
	@echo "  test_interrupt_tx_empty            - TX_EMPTY interrupt"
	@echo "  test_interrupt_tx_abrt             - TX_ABRT interrupt sources"
	@echo "  test_interrupt_stop_det            - STOP_DET interrupt"
	@echo ""
	@echo "=== Register Tests (reg/) ==="
	@echo "  test_reg_con_write_read            - CON register all fields"
	@echo "  test_reg_tar_sar                   - TAR/SAR registers"
	@echo "  test_reg_hcnt_lcnt_speed           - HCNT/LCNT speed config"
	@echo "  test_reg_enable_abort              - ENABLE/ABORT registers"
	@echo "  test_reg_undefined_addr            - Undefined addr returns 0"
	@echo ""
	@echo "=== Constrained Random Tests (rand/) ==="
	@echo "  test_rand_master_write             - Random data/addr/length"
	@echo "  test_rand_master_read              - Random length/addr"
	@echo "  test_rand_slave_receive            - Random data/length"
	@echo "  test_rand_reg_access               - Random register sequence"
	@echo "  test_rand_interrupt_mask           - Random interrupt mask combos"
