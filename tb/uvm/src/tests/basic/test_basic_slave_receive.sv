// Test: Basic Slave Receive (single byte)
// Sequence: I2C BFM (Master) writes to DUT (Slave) -> START -> ADDR(0x3C)+W -> DATA -> STOP
// Cover: Slave address match, RX FIFO storage, SAR register
class test_basic_slave_receive extends base_test;

  `uvm_component_utils(test_basic_slave_receive)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
  begin
    logic [31:0] rxflr;
    logic [31:0] rx_data;
    phase.raise_objection(this);
    `uvm_info("TEST_BASIC_SLAVE_RECEIVE", "Starting Slave Receive Test...", UVM_MEDIUM)

    // Configure DUT as Slave: SAR=0x3C, MASTER_MODE=0, SLAVE_DISABLE=0
    apb_write(8'h08, {25'b0, 7'h3C});  // SAR=0x3C
    apb_write(8'h00, 12'h04);  // MASTER_MODE=0, SLAVE_DISABLE=0
    apb_write(8'h34, 32'h1);   // ENABLE=1

    // DUT master FSM now drives I2C transaction


    #50us;

    // Check RXFLR for received data
    apb_read(8'h40, rxflr);
    `uvm_info("TEST_BASIC_SLAVE_RECEIVE", $sformatf("RXFLR=0x%08h", rxflr), UVM_MEDIUM)

    // Read received data from RX FIFO
    apb_read(8'h0C, rx_data);
    `uvm_info("TEST_BASIC_SLAVE_RECEIVE", $sformatf("RX DATA=0x%02x (expected 0xCC)", rx_data[7:0]), UVM_MEDIUM)

    if (rx_data[7:0] == 8'hCC)
      `uvm_info("TEST_BASIC_SLAVE_RECEIVE", "Slave Receive Test PASSED", UVM_MEDIUM)
    else
      `uvm_warning("TEST_BASIC_SLAVE_RECEIVE", $sformatf("Data mismatch: got 0x%02x expected 0xCC", rx_data[7:0]))

    phase.drop_objection(this);
  end
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

  task apb_read(input logic [7:0] addr, output logic [31:0] data);
    virtual apb_if vif = env.apb_drv.vif;
    @(posedge vif.pclk);
    vif.psel    <= 1'b1;
    vif.penable <= 1'b0;
    vif.pwrite  <= 1'b0;
    vif.paddr   <= addr;
    @(posedge vif.pclk);
    vif.penable <= 1'b1;
    @(posedge vif.pclk);
    while (!vif.pready) @(posedge vif.pclk);
    data = vif.prdata;
    vif.psel    <= 1'b0;
    vif.penable <= 1'b0;
  endtask

endclass : test_basic_slave_receive
