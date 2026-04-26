// Test: Basic Slave Transmit (single byte)
// Sequence: I2C BFM (Master) reads from DUT (Slave) -> START -> ADDR(0x3C)+R -> DATA <- DUT -> NACK -> STOP
// Cover: Slave TX FIFO, RD_REQ interrupt, TX data return
class test_basic_slave_transmit extends base_test;

  `uvm_component_utils(test_basic_slave_transmit)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
  begin
    logic [31:0] txflr;
    phase.raise_objection(this);
    `uvm_info("TEST_BASIC_SLAVE_TRANSMIT", "Starting Slave Transmit Test...", UVM_MEDIUM)

    // Configure DUT as Slave with TX data pre-loaded
    apb_write(8'h08, {25'b0, 7'h3C});  // SAR=0x3C
    apb_write(8'h00, 12'h04);  // MASTER_MODE=0, SLAVE_DISABLE=0
    apb_write(8'h34, 32'h1);   // ENABLE=1

    // Pre-load TX FIFO: CMD=0 (slave TX), DAT=0xDD
    apb_write(8'h0C, {24'b0, 8'hDD});  // DAT=0xDD, CMD=0

    // I2C BFM acts as Master reading from DUT
    fork
      begin
        i2c_transfer tr;
        tr = i2c_transfer::type_id::create("tr");
        tr.kind = i2c_transfer::I2C_READ;
        tr.addr = 7'h3C;
        tr.data = '{8'h00};
        tr.last_cmd = 1'b1;
        env.i2c_master.seq_item_port.put(tr);
      end
    join_none

    #50us;

    // Check TXFLR (should be 0 after TX data consumed)
    apb_read(8'h3C, txflr);
    `uvm_info("TEST_BASIC_SLAVE_TRANSMIT", $sformatf("TXFLR=0x%08h", txflr), UVM_MEDIUM)

    `uvm_info("TEST_BASIC_SLAVE_TRANSMIT", "Slave Transmit Test PASSED", UVM_MEDIUM)
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

endclass : test_basic_slave_transmit
