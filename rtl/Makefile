# I2C Controller - RTL Simulation Makefile
# For Synopsys VCS

PROJECT_ROOT := $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))
RTL_DIR      := $(PROJECT_ROOT)/rtl
TB_DIR       := $(PROJECT_ROOT)/tb
SIM_DIR      := $(PROJECT_ROOT)/sim

# Tool settings
VCS          := vcs
VCS_FLAGS    := -full64 -P $(VCSINSTALL)/lib/vcsmx_shared.vpo \
                -notice -reportstats \
                +warn=none -j4 \
                -sverilog \
                -timescale=1ns/1ps \
                -CFLAGS "-O3" \
                -LDFLAGS "-O3"

# Compiling with debug: add -debug_access+all -debug_region+cell
# Compiling for XMR:    add -assert enable_xprop

# Top-levels
RTL_TOP      := i2c_ctrl_top
TB_TOP       := tb_i2c_ctrl

# Filelist
RTL_FLIST    := $(RTL_DIR)/filelist.f
TB_FLIST     := $(wildcard $(TB_DIR)/*.sv)

# Coverage
COV_DIR      := $(SIM_DIR)/coverage
COV_FLAGS    := -cm line+cond+fsm+branch+tgl

# ============================================================
# Targets
# ============================================================

.PHONY: sim compile run clean help

# Default: run simulation
sim: compile run

# Compile only
compile:
	@echo "=== Compiling RTL ==="
	$(VCS) $(VCS_FLAGS) \
		-f $(RTL_FLIST) \
		$(TB_FLIST) \
		-top $(TB_TOP) \
		-o $(SIM_DIR)/simv \
		-cm_name $(TB_TOP) \
		$(COV_FLAGS)
	@echo "=== Compilation done ==="

# Run simulation
run: compile
	@echo "=== Running simulation ==="
	cd $(SIM_DIR) && ./simv +vcs+lic+wait -l sim.log

# Quick run (no coverage)
run_quick: compile
	cd $(SIM_DIR) && ./simv +vcs+lic+wait -l sim.log

# Clean build files
clean:
	rm -rf $(SIM_DIR)/*.log $(SIM_DIR)/*.vpd $(SIM_DIR)/*.fsdb \
	       $(SIM_DIR)/simv* $(SIM_DIR)/csrc $(SIM_DIR)/DVEfiles \
	       $(COV_DIR)

# Clean everything
cleanall: clean
	find . -name "*.vcd" -delete -o -name "*.log" -delete

# Help
help:
	@echo "I2C Controller - VCS Simulation Makefile"
	@echo ""
	@echo "Targets:"
	@echo "  sim         - Full compile + run (default)"
	@echo "  compile     - Compile RTL + TB only"
	@echo "  run         - Run existing simulation"
	@echo "  run_quick   - Run without coverage"
	@echo "  clean       - Remove sim artifacts"
	@echo "  cleanall    - Remove all generated files"
	@echo ""
	@echo "Environment:"
	@echo "  VCS          = $(VCS)"
	@echo "  RTL_DIR      = $(RTL_DIR)"
	@echo "  TB_DIR       = $(TB_DIR)"
	@echo "  SIM_DIR      = $(SIM_DIR)"
