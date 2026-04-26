# I2C Controller - VCS Simulation Makefile
# Top-level sim Makefile for UVM verification

PROJECT_ROOT := $(shell cd $(dir $(lastword $(MAKEFILE_LIST)))/.. && pwd)
RTL_FLIST    := $(PROJECT_ROOT)/rtl/filelist.f
TB_FLIST     := $(PROJECT_ROOT)/tb/uvm/filelist.f
UVM_DIR      := $(VCS_HOME)/etc/uvm

# Tool
VCS          := vcs
VCS_FLAGS    := -sverilog \
                -timescale=1ns/1ps \
                -full64 \
                -ntb_opts uvm \
                -cm line+cond+fsm+branch+tgl \
                -cm_name i2c_ctrl \
                +incdir+$(UVM_DIR) \
                -notice -reportstats

# Test name (override with TEST=<name>)
TEST         ?= test_master_single_write

# Output
SIMV         := $(PROJECT_ROOT)/sim/simv
COMPILE_LOG  := $(PROJECT_ROOT)/sim/compile.log
SIM_LOG      := $(PROJECT_ROOT)/sim/$(TEST).log

.PHONY: compile sim clean help

# Compile RTL + TB
compile: clean_sim
	@echo "=== Compiling i2c_controller (RTL + UVM TB) ==="
	@echo "PROJECT_ROOT=$(PROJECT_ROOT)"
	cd $(PROJECT_ROOT) && \
	$(VCS) $(VCS_FLAGS) \
		-f $(RTL_FLIST) \
		-f $(TB_FLIST) \
		-top tb_top \
		-o $(SIMV) \
		2>&1 | tee $(COMPILE_LOG)
	@echo "=== Compilation done ==="

# Run simulation
sim: compile
	@echo "=== Running test: $(TEST) ==="
	cd $(PROJECT_ROOT)/sim && \
	./simv +vcs+lic+wait -l $(SIM_LOG) 2>&1 | tee $(SIM_LOG)

# Run specific test
run TEST=$(TEST): sim

# Quick run (no coverage, no license wait)
run_quick TEST=$(TEST):
	cd $(PROJECT_ROOT)/sim && \
	./simv -l $(SIM_LOG) 2>&1 | tee $(SIM_LOG)

# Clean simulation artifacts
clean:
	rm -rf $(PROJECT_ROOT)/sim/simv* \
	       $(PROJECT_ROOT)/sim/*.log \
	       $(PROJECT_ROOT)/sim/*.vpd \
	       $(PROJECT_ROOT)/sim/*.fsdb \
	       $(PROJECT_ROOT)/sim/csrc \
	       $(PROJECT_ROOT)/sim/DVEfiles \
	       $(PROJECT_ROOT)/sim/vcs.dir

clean_sim:
	rm -rf $(PROJECT_ROOT)/sim/simv* \
	       $(PROJECT_ROOT)/sim/csrc \
	       $(PROJECT_ROOT)/sim/DVEfiles

# Coverage report
coverage_report:
	urg -dir $(PROJECT_ROOT)/sim/vcs.dir -report $(PROJECT_ROOT)/sim/coverage_report

help:
	@echo "I2C Controller - VCS Simulation Makefile"
	@echo ""
	@echo "Targets:"
	@echo "  make compile                - Compile RTL + TB (no sim run)"
	@echo "  make sim TEST=<test>        - Compile + run test"
	@echo "  make run TEST=<test>        - Same as sim"
	@echo "  make run_quick TEST=<test>  - Run without license wait"
	@echo "  make clean                  - Clean all sim artifacts"
	@echo "  make coverage_report        - Generate coverage report"
	@echo ""
	@echo "Available tests:"
	@echo "  test_master_single_write"
	@echo "  test_master_single_read"
	@echo "  test_master_burst_write"
	@echo "  test_slave_receive"
	@echo "  test_slave_transmit"
