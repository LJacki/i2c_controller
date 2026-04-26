# I2C Controller Verification - VCS Source Files

# === INTERFACES (must be at top level, before package) ===
+incdir+tb/uvm/src
tb/uvm/src/apb/apb_if.sv
tb/uvm/src/i2c/i2c_if.sv
tb/uvm/src/uvm_macros.svh

# === PACKAGE (interfaces above) ===
tb/uvm/src/i2c_ctrl_pkg.sv

# APB BFM
tb/uvm/src/apb/apb_transfer.sv
tb/uvm/src/apb/apb_driver.sv
tb/uvm/src/apb/apb_monitor.sv

# I2C BFM
tb/uvm/src/i2c/i2c_transfer.sv
tb/uvm/src/i2c/i2c_master_agent.sv
tb/uvm/src/i2c/i2c_slave_agent.sv

# Environment
tb/uvm/src/env/scoreboard.sv
tb/uvm/src/env/i2c_ctrl_env.sv

# Tests - infrastructure
tb/uvm/src/tests/test_cfg.sv
tb/uvm/src/tests/base_test.sv

# Tests - basic directed
tb/uvm/src/tests/basic/test_basic_master_single_write.sv
tb/uvm/src/tests/basic/test_basic_master_burst_write.sv
tb/uvm/src/tests/basic/test_basic_master_single_read.sv
tb/uvm/src/tests/basic/test_basic_master_burst_read.sv
tb/uvm/src/tests/basic/test_basic_master_repeated_start.sv
tb/uvm/src/tests/basic/test_basic_master_addr_nack.sv
tb/uvm/src/tests/basic/test_basic_master_data_nack.sv
tb/uvm/src/tests/basic/test_basic_slave_receive.sv
tb/uvm/src/tests/basic/test_basic_slave_transmit.sv
tb/uvm/src/tests/basic/test_basic_slave_addr_no_match.sv

# Tests - interrupt
tb/uvm/src/tests/interrupt/test_interrupt_rx_full.sv
tb/uvm/src/tests/interrupt/test_interrupt_tx_empty.sv
tb/uvm/src/tests/interrupt/test_interrupt_tx_abrt.sv
tb/uvm/src/tests/interrupt/test_interrupt_stop_det.sv

# Tests - register
tb/uvm/src/tests/reg/test_reg_con_write_read.sv
tb/uvm/src/tests/reg/test_reg_tar_sar.sv
tb/uvm/src/tests/reg/test_reg_hcnt_lcnt_speed.sv
tb/uvm/src/tests/reg/test_reg_enable_abort.sv
tb/uvm/src/tests/reg/test_reg_undefined_addr.sv

# Tests - constrained random
tb/uvm/src/tests/rand/test_rand_master_write.sv
tb/uvm/src/tests/rand/test_rand_master_read.sv
tb/uvm/src/tests/rand/test_rand_slave_receive.sv
tb/uvm/src/tests/rand/test_rand_reg_access.sv
tb/uvm/src/tests/rand/test_rand_interrupt_mask.sv

# Testbench top
tb/uvm/src/tests/tb_top.sv

# RTL Stub
tb/uvm/src/i2c_ctrl_top_stub.sv
