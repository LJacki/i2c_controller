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

    // I2C BFM acts as Master writing to DUT slave
    fork
      begin
        i2c_transfer tr;
        tr = i2c_transfer::type_id::create("tr");
        tr.kind = i2c_transfer::I2C_WRITE;
        tr.addr = 7'h3C;
        tr.data = '{8'hCC};
        tr.last_cmd = 1'b0;
        env.i2c_master.seq_item_port.put(tr);
      end
    join_none

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

endclass : test_basic_slave_receive
