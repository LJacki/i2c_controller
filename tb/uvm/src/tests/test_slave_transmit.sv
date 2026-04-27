// Test: Slave Transmit
// I2C BFM acts as Master reading from DUT
// Sequence: START -> ADDR(0x3C)+R -> DATA <- DUT -> NACK -> STOP
class test_slave_transmit extends base_test;

  `uvm_component_utils(test_slave_transmit)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    `uvm_info("TEST_SLAVE_TRANSMIT", "Starting Slave Transmit Test...", UVM_MEDIUM)

    // Configure DUT as slave with TX data pre-loaded
    apb_write(8'h08, {25'b0, 7'h3C});  // I2C_SAR = 0x3C
    apb_write(8'h00, 12'h04);  // MASTER_MODE=0, SLAVE_DISABLE=0
    apb_write(8'h30, 32'h1);  // ENABLE=1

    // Pre-load TX FIFO with data (CMD=0, DAT=0xCC)
    apb_write(8'h0C, {24'b0, 8'hCC});

    // I2C BFM initiates read transaction from DUT
    fork
      begin
        logic [7:0] rd_data;
        env.i2c_master.drive_i2c_read(7'h3C, rd_data);
      end
    join_none

    #50us;

    `uvm_info("TEST_SLAVE_TRANSMIT", "Slave Transmit Test Completed", UVM_MEDIUM)
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

endclass : test_slave_transmit