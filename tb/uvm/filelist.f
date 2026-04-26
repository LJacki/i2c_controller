// I2C Controller Verification - VCS Source Files
//
// All SystemVerilog source files for UVM verification

# UVM and interfaces
+incdir+./src
./src/uvm_macros.svh

# Interfaces
./src/apb/apb_if.sv
./src/i2c/i2c_if.sv

# Package
./src/i2c_ctrl_pkg.sv

# APB BFM
./src/apb/apb_transfer.sv
./src/apb/apb_driver.sv
./src/apb/apb_monitor.sv

# I2C BFM
./src/i2c/i2c_transfer.sv
./src/i2c/i2c_master_agent.sv
./src/i2c/i2c_slave_agent.sv

# Environment
./src/env/scoreboard.sv
./src/env/i2c_ctrl_env.sv

# Tests - infrastructure
./src/tests/test_cfg.sv
./src/tests/base_test.sv

# Tests - basic directed (Master/Slave functional)
./src/tests/basic/test_basic_master_single_write.sv
./src/tests/basic/test_basic_master_burst_write.sv
./src/tests/basic/test_basic_master_single_read.sv
./src/tests/basic/test_basic_master_burst_read.sv
./src/tests/basic/test_basic_master_repeated_start.sv
./src/tests/basic/test_basic_master_addr_nack.sv
./src/tests/basic/test_basic_master_data_nack.sv
./src/tests/basic/test_basic_slave_receive.sv
./src/tests/basic/test_basic_slave_transmit.sv
./src/tests/basic/test_basic_slave_addr_no_match.sv

# Tests - interrupt
./src/tests/interrupt/test_interrupt_rx_full.sv
./src/tests/interrupt/test_interrupt_tx_empty.sv
./src/tests/interrupt/test_interrupt_tx_abrt.sv
./src/tests/interrupt/test_interrupt_stop_det.sv

# Tests - register
./src/tests/reg/test_reg_con_write_read.sv
./src/tests/reg/test_reg_tar_sar.sv
./src/tests/reg/test_reg_hcnt_lcnt_speed.sv
./src/tests/reg/test_reg_enable_abort.sv
./src/tests/reg/test_reg_undefined_addr.sv

# Tests - constrained random
./src/tests/rand/test_rand_master_write.sv
./src/tests/rand/test_rand_master_read.sv
./src/tests/rand/test_rand_slave_receive.sv
./src/tests/rand/test_rand_reg_access.sv
./src/tests/rand/test_rand_interrupt_mask.sv

# Testbench top
./src/tests/tb_top.sv

# RTL Stub (placeholder until real RTL available)
./src/i2c_ctrl_top_stub.sv
