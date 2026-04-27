// Test: Slave Receive
// I2C BFM acts as Master, DUT as Slave
// Sequence: START -> ADDR(0x3C)+W -> DATA -> STOP
class test_slave_receive extends base_test;

  `uvm_component_utils(test_slave_receive)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    `uvm_info("TEST_SLAVE_RECEIVE", "Starting Slave Receive Test...", UVM_MEDIUM)

    // Configure DUT as slave: SAR=0x3C, MASTER_MODE=0, SLAVE_DISABLE=0
    apb_write(8'h08, {25'b0, 7'h3C});  // I2C_SAR = 0x3C
    apb_write(8'h00, 12'h04);  // MASTER_MODE=0, SLAVE_DISABLE=0
    apb_write(8'h30, 32'h1);  // ENABLE=1

    // I2C BFM initiates write transaction to DUT
    fork
      begin
        env.i2c_master.drive_i2c_write(7'h3C, '{8'hBB});
      end
    join

    #50us;

    `uvm_info("TEST_SLAVE_RECEIVE", "Slave Receive Test Completed", UVM_MEDIUM)
    phase.drop_objection(this);
  endtask

  task apb_write(input logic [7:0] addr, input logic [31:0] data);
    virtual apb_if vif = env.apb_drv.vif;
    @(posedge vif.pclk);
    vif.psel    <= 1'b1;
    vif.penable <= 1'b0;
    vif.pwrite  <= 1'b1;
    vif.paddr   <= addr;
    vif.pwdata  <= data;
    @(posedge vif.pclk);
    vif.penable <= 1'b1;
    @(posedge vif.pclk);
    while (!vif.pready) @(posedge vif.pclk);
    vif.psel    <= 1'b0;
    vif.penable <= 1'b0;
  endtask

endclass : test_slave_receive