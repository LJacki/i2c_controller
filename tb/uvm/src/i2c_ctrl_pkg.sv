// I2C Controller Package - top-level package for UVM verification
`timescale 1ns/1ps

package i2c_ctrl_pkg;

  // Import UVM library
  import uvm_pkg::*;

  // Include macros
  `include "uvm_macros.svh"

  // APB components
  `include "apb/apb_transfer.sv"
  `include "apb/apb_driver.sv"
  `include "apb/apb_monitor.sv"

  // I2C components
  `include "i2c/i2c_transfer.sv"
  `include "i2c/i2c_master_agent.sv"
  `include "i2c/i2c_slave_agent.sv"
  `include "i2c/i2c_bus_monitor.sv"
  `include "i2c/i2c_protocol_checker.sv"

  // Environment
  `include "env/scoreboard.sv"
  `include "env/i2c_ctrl_env.sv"

  // Test infrastructure
  `include "tests/test_cfg.sv"
  `include "tests/base_test.sv"

  // === Basic Directed Tests ===
  `include "tests/basic/test_basic_master_single_write.sv"
  `include "tests/basic/test_basic_master_burst_write.sv"
  `include "tests/basic/test_basic_master_single_read.sv"
  `include "tests/basic/test_basic_master_burst_read.sv"
  `include "tests/basic/test_basic_master_repeated_start.sv"
  `include "tests/basic/test_basic_master_addr_nack.sv"
  `include "tests/basic/test_basic_master_data_nack.sv"
  `include "tests/basic/test_basic_slave_receive.sv"
  `include "tests/basic/test_basic_slave_transmit.sv"
  `include "tests/basic/test_basic_slave_addr_no_match.sv"

  // === Interrupt Tests ===
  `include "tests/interrupt/test_interrupt_rx_full.sv"
  `include "tests/interrupt/test_interrupt_tx_empty.sv"
  `include "tests/interrupt/test_interrupt_tx_abrt.sv"
  `include "tests/interrupt/test_interrupt_stop_det.sv"

  // === Register Tests ===
  `include "tests/reg/test_reg_con_write_read.sv"
  `include "tests/reg/test_reg_tar_sar.sv"
  `include "tests/reg/test_reg_hcnt_lcnt_speed.sv"
  `include "tests/reg/test_reg_enable_abort.sv"
  `include "tests/reg/test_reg_undefined_addr.sv"

  // === Constrained Random Tests ===
  `include "tests/rand/test_rand_master_write.sv"
  `include "tests/rand/test_rand_master_read.sv"
  `include "tests/rand/test_rand_slave_receive.sv"
  `include "tests/rand/test_rand_reg_access.sv"
  `include "tests/rand/test_rand_interrupt_mask.sv"

endpackage : i2c_ctrl_pkg
