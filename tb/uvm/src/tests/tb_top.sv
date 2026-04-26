// Testbench Top - instantiates DUT and connects BFM interfaces
`timescale 1ns/1ps

module tb_top;

  import uvm_pkg::*;
  import i2c_ctrl_pkg::*;

  // Clock and reset
  bit pclk;
  bit presetn;

  // APB signals
  bit        psel;
  bit        penable;
  bit        pwrite;
  bit [7:0]  paddr;
  bit [31:0] pwdata;
  bit [31:0] prdata;
  bit        pready;

  // I2C signals (logic type to allow multiple drivers)
  logic scl_i;
  logic scl_o;
  logic scl_oe;
  logic sda_i;
  logic sda_o;
  logic sda_oe;
  logic intr;

  // Instantiate APB interface
  apb_if apb_if_inst (.pclk(pclk), .presetn(presetn));

  // Instantiate I2C interface
  i2c_if i2c_if_inst ();

  // Clock generation
  initial begin
    pclk = 0;
    forever #5ns pclk = ~pclk;  // 100MHz clock
  end

  // Reset generation
  initial begin
    presetn = 0;
    #100ns;
    presetn = 1;
  end

  // I2C wire resolution (multiple drivers via assign - tri-state behavior)
  assign scl_i = (scl_oe) ? scl_o : 1'b1;  // pull-up when OE=0
  assign sda_i = (sda_oe) ? sda_o : 1'b1;  // pull-up when OE=0

  // DUT instantiation
  i2c_ctrl_top dut (
    .pclk(pclk),
    .presetn(presetn),
    .psel(apb_if_inst.psel),
    .penable(apb_if_inst.penable),
    .pwrite(apb_if_inst.pwrite),
    .paddr(apb_if_inst.paddr),
    .pwdata(apb_if_inst.pwdata),
    .prdata(apb_if_inst.prdata),
    .pready(apb_if_inst.pready),
    .scl_i(scl_i),
    .scl_o(scl_o),
    .scl_oe(scl_oe),
    .sda_i(sda_i),
    .sda_o(sda_o),
    .sda_oe(sda_oe),
    .intr(intr)
  );

  // UVM run task
  initial begin
    // Set virtual interfaces in config_db
    uvm_config_db #(virtual apb_if)::set(null, "uvm_test_top.env.apb_drv", "vif", apb_if_inst);
    uvm_config_db #(virtual apb_if)::set(null, "uvm_test_top.env.apb_mon", "vif", apb_if_inst);
    uvm_config_db #(virtual i2c_if)::set(null, "uvm_test_top.env.i2c_master", "vif", i2c_if_inst);
    uvm_config_db #(virtual i2c_if)::set(null, "uvm_test_top.env.i2c_slave", "vif", i2c_if_inst);

    // Run test
    run_test();
  end

endmodule : tb_top
