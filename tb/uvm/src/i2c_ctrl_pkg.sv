// I2C Controller Package - top-level package for UVM verification
`timescale 1ns/1ps

package i2c_ctrl_pkg;

  // Import UVM library
  import uvm_pkg::*;

  // Include macros
  `include "uvm_macros.svh"

  // Interfaces
  `include "apb/apb_if.sv"
  `include "i2c/i2c_if.sv"

  // APB components
  `include "apb/apb_transfer.sv"
  `include "apb/apb_driver.sv"
  `include "apb/apb_monitor.sv"

  // I2C components
  `include "i2c/i2c_transfer.sv"
  `include "i2c/i2c_master_agent.sv"
  `include "i2c/i2c_slave_agent.sv"

  // Environment
  `include "env/scoreboard.sv"
  `include "env/i2c_ctrl_env.sv"

  // Test infrastructure
  `include "tests/test_cfg.sv"
  `include "tests/base_test.sv"
  `include "tests/test_master_single_write.sv"
  `include "tests/test_master_single_read.sv"
  `include "tests/test_master_burst_write.sv"
  `include "tests/test_slave_receive.sv"
  `include "tests/test_slave_transmit.sv"

endpackage : i2c_ctrl_pkg