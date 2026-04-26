# I2C Controller Verification - VCS Source Files
#
# All SystemVerilog source files for UVM verification

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

# Tests
./src/tests/test_cfg.sv
./src/tests/base_test.sv
./src/tests/test_master_single_write.sv
./src/tests/test_master_single_read.sv
./src/tests/test_master_burst_write.sv
./src/tests/test_slave_receive.sv
./src/tests/test_slave_transmit.sv
./src/tests/tb_top.sv

# RTL Stub (placeholder until real RTL available)
./src/i2c_ctrl_top_stub.sv