// Test Configuration
class test_cfg extends uvm_object;

  // I2C speed mode
  typedef enum { STANDARD=1, FAST=2 } speed_mode_e;
  rand speed_mode_e speed_mode = FAST;

  // I2C slave address
  rand bit [6:0] i2c_slave_addr = 7'h3C;

  // Master target address
  rand bit [6:0] i2c_master_target = 7'h3C;

  // I2C frequency parameters (based on speed mode)
  real period_standard = 10us;  // 100kHz
  real period_fast     = 2.5us; // 400kHz

  // APB clock period
  real pclk_period = 10ns;  // 100MHz

  `uvm_object_utils_begin(test_cfg)
    `uvm_field_enum(speed_mode_e, speed_mode, UVM_DEFAULT)
    `uvm_field_int(i2c_slave_addr, UVM_DEFAULT)
    `uvm_field_int(i2c_master_target, UVM_DEFAULT)
  `uvm_object_utils_end

  function new(string name = "test_cfg");
    super.new(name);
  endfunction

  function void set_speed(speed_mode_e mode);
    speed_mode = mode;
  endfunction

endclass : test_cfg