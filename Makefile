PROJECT_DIR := $(shell pwd)
SIM_DIR     := $(PROJECT_DIR)/sim
TB_DIR      := $(PROJECT_DIR)/tb/uvm
RTL_DIR     := $(PROJECT_DIR)/rtl
TESTS       := test_basic_master_single_write \
               test_basic_master_single_read \
               test_basic_master_burst_write \
               test_basic_master_burst_read \
               test_basic_master_addr_nack \
               test_basic_master_data_nack \
               test_basic_master_repeated_start \
               test_basic_slave_receive \
               test_basic_slave_transmit \
               test_basic_slave_addr_no_match \
               test_interrupt_rx_full \
               test_interrupt_tx_empty \
               test_interrupt_tx_abrt \
               test_interrupt_stop_det \
               test_rand_master_write \
               test_rand_master_read \
               test_rand_slave_receive \
               test_rand_interrupt_mask \
               test_rand_reg_access \
               test_reg_con_write_read \
               test_reg_enable_abort \
               test_reg_hcnt_lcnt_speed \
               test_reg_tar_sar \
               test_reg_undefined_addr

VCS_HOME    := /eda/synopsys/vcs/O-2018.09-SP2/vcs/O-2018.09-SP2
SCL_HOME    := /home/xiaoai
export PATH  := /home/xiaoai/bin:$(VCS_HOME)/bin:$(PATH)
export LD_PRELOAD := /home/xiaoai/lib64_compat/libpthread_override.so

VCS_OPTS    := -sverilog -f $(RTL_DIR)/filelist.f -f $(TB_DIR)/filelist.f \
               -ntb_opts uvm-1.1 -full64 -timescale=1ns/1ps \
               -top tb_top -o $(SIM_DIR)/simv \
               -cm line+cond+fsm+branch+tgl

.PHONY: all compile compile_nocov sim regress cov_report clean help

all: compile

compile:
	@mkdir -p $(SIM_DIR)
	@echo "=== Compiling with coverage ==="
	bash -c "source $(SCL_HOME)/synopsys_env_setup.sh && cd $(PROJECT_DIR) && vcs $(VCS_OPTS)" 2>&1 | tail -5

compile_nocov:
	@mkdir -p $(SIM_DIR)
	bash -c "source $(SCL_HOME)/synopsys_env_setup.sh && cd $(PROJECT_DIR) && vcs -sverilog -f $(RTL_DIR)/filelist.f -f $(TB_DIR)/filelist.f -ntb_opts uvm-1.1 -full64 -timescale=1ns/1ps -top tb_top -o $(SIM_DIR)/simv" 2>&1 | tail -5

sim:
	@if [ -z "$(TEST)" ]; then echo "Usage: make sim TEST=test_basic_master_single_write"; exit 1; fi
	bash -c "source $(SCL_HOME)/synopsys_env_setup.sh && cd $(PROJECT_DIR) && ./$(SIM_DIR)/simv +UVM_TESTNAME=$(TEST) +UVM_VERBOSITY=UVM_MEDIUM -cm line+cond+fsm+branch+tgl"

regress: compile
	@mkdir -p $(SIM_DIR)/cov
	@echo "=== Running regression (24 tests) ==="
	@passed=0; failed=0; \
	for t in $(TESTS); do \
		i=$$(printf "%02d" $$passed); \
		mkdir -p $(SIM_DIR)/cov/test_$$i; \
		echo "  Running: $$t ..."; \
		bash -c "source $(SCL_HOME)/synopsys_env_setup.sh && cd $(PROJECT_DIR) && ./$(SIM_DIR)/simv +UVM_TESTNAME=$$t +UVM_VERBOSITY=UVM_MEDIUM -cm line+cond+fsm+branch+tgl -cm_dir $(SIM_DIR)/cov/test_$$i/test.vdb" \
			2>/dev/null > $(SIM_DIR)/cov/test_$$i.log; \
		if grep -q "UVM_FATAL @" $(SIM_DIR)/cov/test_$$i.log; then \
			echo "  FAIL: $$t"; failed=$$((failed+1)); \
		else \
			echo "  PASS: $$t"; passed=$$((passed+1)); \
		fi; \
	done; \
	echo ""; echo "========================================"; \
	echo "Regression: PASS=$$passed FAIL=$$failed"; \
	echo "========================================"

cov_report: regress
	@echo "=== Merging coverage ==="
	@bash -c "source $(SCL_HOME)/synopsys_env_setup.sh && cd $(PROJECT_DIR) && \
		DIRS=\"-dir $(SIM_DIR)/simv.vdb\"; \
		for i in \$$(seq 0 23); do \
			DIRS=\"\$$DIRS -dir $(SIM_DIR)/cov/test_\$$(printf %02d \$$i)/test.vdb\"; \
		done; \
		urg \$$DIRS -report $(SIM_DIR)/cov/report" 2>&1 | tail -5
	@echo ""; echo "Coverage report: $(SIM_DIR)/cov/report/dashboard.html"

clean:
	@rm -rf $(SIM_DIR) $(PROJECT_DIR)/csrc $(PROJECT_DIR)/cm.log \
	       $(PROJECT_DIR)/vc_hdrs.h $(PROJECT_DIR)/ucli.key && \
	       echo "All simulation artifacts cleaned"

help:
	@echo "I2C Controller UVM Simulation Makefile"
	@echo ""
	@echo "  make compile         - Compile RTL+TB with coverage"
	@echo "  make compile_nocov  - Compile without coverage"
	@echo "  make sim TEST=name   - Run single test"
	@echo "  make regress         - Run all 24 tests (per-test coverage)"
	@echo "  make cov_report     - Generate merged coverage report"
	@echo "  make clean          - Clean ALL simulation artifacts"
	@echo "  make help           - Show this help"
