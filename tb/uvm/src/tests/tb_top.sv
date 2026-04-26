// Testbench Top - instantiates DUT and connects BFM interfaces
`timescale 1ns/1ps

module tb_top;

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

  // I2C signals
  bit scl_i;
  bit scl_o;
  bit scl_oe;
  bit sda_i;
  bit sda_o;
  bit sda_oe;
  bit intr;

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

  // Initialize I2C signals with pull-ups (wire-AND simulation)
  initial begin
    scl_i = 1'b1;
    sda_i = 1'b1;
  end

  // Drive I2C outputs when enabled (simple wire-AND behavior)
  always begin
    #1;
    // Weak pull-up simulation
    if (scl_oe == 1'b0) scl_i <= #(1) 1'b1;
    if (sda_oe == 1'b0) sda_i <= #(1) 1'b1;
  end

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

  // I2C wire resolution (multiple drivers)
  assign scl_i = (scl_oe) ? scl_o : 1'b1;
  assign sda_i = (sda_oe) ? sda_o : 1'b1;

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