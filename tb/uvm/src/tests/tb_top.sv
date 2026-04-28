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

  // I2C signals ( DUT outputs via i2c_if )
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

  // DUT instantiation - connects to i2c_if signals
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
    .scl_i(i2c_if_inst.scl_i),
    .scl_o(i2c_if_inst.scl_o),
    .scl_oe(i2c_if_inst.scl_oe),
    .sda_i(i2c_if_inst.sda_i),
    .sda_o(i2c_if_inst.sda_o),
    .sda_oe(i2c_if_inst.sda_oe),
    .intr(intr)
  );

  // ========================
  // Bus Activity Monitor (uses i2c_if signals)
  // ========================
  bit prev_scl_oe = 1'b0;
  bit prev_scl_i  = 1'b1;
  bit prev_sda_i  = 1'b1;
  int scl_oe_changes = 0;
  integer mon_fd;

  initial begin
    mon_fd = $fopen("/tmp/i2c_bus_activity.log", "w");
    $fwrite(mon_fd, "Time(ns),Event,scl_oe,scl_i,sda_oe,sda_i\n");
  end

  always @(posedge pclk) begin
    if (presetn) begin
      // Monitor scl_oe changes
      if (i2c_if_inst.scl_oe !== prev_scl_oe) begin
        $display("BUS: time=%t scl_oe=%b scl_i=%b sda_oe=%b sda_i=%b [changes=%0d]",
                 $time, i2c_if_inst.scl_oe, i2c_if_inst.scl_i,
                 i2c_if_inst.sda_oe, i2c_if_inst.sda_i, scl_oe_changes);
        prev_scl_oe = i2c_if_inst.scl_oe;
        if (i2c_if_inst.scl_oe !== 1'bx) scl_oe_changes++;
      end
      // Detect START: SDA falls while SCL=1
      if (prev_sda_i === 1'b1 && i2c_if_inst.sda_i === 1'b0 && i2c_if_inst.scl_i === 1'b1) begin
        $display("[BUS_MON %t] *** START CONDITION *** scl_i=%b sda_i=%b scl_oe=%b",
                 $time, i2c_if_inst.scl_i, i2c_if_inst.sda_i, i2c_if_inst.scl_oe);
      end
      // Detect STOP: SDA rises while SCL=1
      if (prev_sda_i === 1'b0 && i2c_if_inst.sda_i === 1'b1 && i2c_if_inst.scl_i === 1'b1) begin
        $display("[BUS_MON %t] *** STOP CONDITION *** scl_i=%b sda_i=%b scl_oe=%b",
                 $time, i2c_if_inst.scl_i, i2c_if_inst.sda_i, i2c_if_inst.scl_oe);
      end
      prev_sda_i <= i2c_if_inst.sda_i;
    end
  end

  final begin
    $fclose(mon_fd);
    $display("Bus monitor: scl_oe_changes=%0d", scl_oe_changes);
  end

  // UVM run task
  initial begin
    uvm_config_db #(virtual apb_if)::set(null, "uvm_test_top.env.apb_drv", "vif", apb_if_inst);
    uvm_config_db #(virtual apb_if)::set(null, "uvm_test_top.env.apb_mon", "vif", apb_if_inst);
    uvm_config_db #(virtual i2c_if)::set(null, "uvm_test_top.env.i2c_master", "vif", i2c_if_inst);
    uvm_config_db #(virtual i2c_if)::set(null, "uvm_test_top.env.i2c_slave", "vif", i2c_if_inst);
    uvm_config_db #(virtual i2c_if)::set(null, "uvm_test_top.env.i2c_bus_mon", "vif", i2c_if_inst);
    uvm_config_db #(virtual i2c_if)::set(null, "uvm_test_top.env.i2c_proto_chk", "vif", i2c_if_inst);
    run_test();
  end

endmodule : tb_top
