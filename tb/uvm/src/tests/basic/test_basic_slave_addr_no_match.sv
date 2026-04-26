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

    // I2C BFM sends wrong address (0x55, not 0x3C)
    fork
      begin
        i2c_transfer tr;
        tr = i2c_transfer::type_id::create("tr");
        tr.kind = i2c_transfer::I2C_WRITE;
        tr.addr = 7'h55;  // Wrong address
        tr.data = '{8'hEE};
        tr.last_cmd = 1'b0;
        env.i2c_master.seq_item_port.put(tr);
      end
    join_none

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

  task apb_write(logic [7:0] addr, logic [31:0] data);
    apb_transfer tr;
    tr = apb_transfer::type_id::create("tr");
    tr.kind  = apb_transfer::APB_WRITE;
    tr.addr  = addr;
    tr.data  = data;
    tr.delay = 0;
    env.apb_drv.seq_item_port.put(tr);
  endtask

  task apb_read(logic [7:0] addr, output logic [31:0] data);
    apb_transfer tr;
    tr = apb_transfer::type_id::create("tr");
    tr.kind = apb_transfer::APB_READ;
    tr.addr = addr;
    tr.data = 0;
    tr.delay = 0;
    env.apb_drv.seq_item_port.put(tr);
    #1us;
    data = tr.data;
  endtask

endclass : test_basic_slave_addr_no_match
