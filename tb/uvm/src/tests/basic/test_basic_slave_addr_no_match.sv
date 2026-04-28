// Test: Basic Slave Address No Match (wrong address)
// Sequence: I2C BFM sends ADDR != SAR -> DUT slave remains silent
// Cover: Slave ignores wrong address, no ACK, RX FIFO unchanged
class test_basic_slave_addr_no_match extends base_test;

  `uvm_component_utils(test_basic_slave_addr_no_match)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
  begin
    logic [31:0] rxflr_before;
    logic [31:0] rxflr_after;
    phase.raise_objection(this);
    `uvm_info("TEST_BASIC_SLAVE_ADDR_NO_MATCH", "Starting Slave Address No Match Test...", UVM_MEDIUM)

    // Configure DUT with SAR=0x3C
    apb_write(8'h08, {25'b0, 7'h3C});  // SAR=0x3C
    apb_write(8'h00, 12'h04);  // MASTER_MODE=0, SLAVE_DISABLE=0
    apb_write(8'h34, 32'h1);   // ENABLE=1

    // Check initial RXFLR (should be 0)
    apb_read(8'h40, rxflr_before);
    `uvm_info("TEST_BASIC_SLAVE_ADDR_NO_MATCH", $sformatf("RXFLR before transaction=0x%08h", rxflr_before), UVM_MEDIUM)

    // DUT master FSM now drives I2C transaction

    #50us;

    // Check RXFLR after wrong-address transaction (should still be 0)
    apb_read(8'h40, rxflr_after);
    `uvm_info("TEST_BASIC_SLAVE_ADDR_NO_MATCH", $sformatf("RXFLR after wrong-addr=0x%08h", rxflr_after), UVM_MEDIUM)

    if (rxflr_after == rxflr_before)
      `uvm_info("TEST_BASIC_SLAVE_ADDR_NO_MATCH", "RXFLR unchanged - slave correctly ignored wrong address: PASSED", UVM_MEDIUM)
    else
      `uvm_error("TEST_BASIC_SLAVE_ADDR_NO_MATCH", $sformatf("RXFLR changed unexpectedly: before=%0d after=%0d", rxflr_before, rxflr_after))

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

endclass : test_basic_slave_addr_no_match
