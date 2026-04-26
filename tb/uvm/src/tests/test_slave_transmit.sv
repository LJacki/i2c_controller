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
        i2c_transfer tr;
        tr = i2c_transfer::type_id::create("tr");
        tr.kind = i2c_transfer::I2C_READ;
        tr.addr = 7'h3C;
        tr.data = '{8'h00};  // dummy, will be filled by slave
        tr.last_cmd = 1'b1;
        env.i2c_master.seq_item_port.put(tr);
      end
    join

    #50us;

    `uvm_info("TEST_SLAVE_TRANSMIT", "Slave Transmit Test Completed", UVM_MEDIUM)
    phase.drop_objection(this);
  endtask

  task apb_write(bit [7:0] addr, bit [31:0] data);
    apb_transfer tr;
    tr = apb_transfer::type_id::create("tr");
    tr.kind  = apb_transfer::APB_WRITE;
    tr.addr  = addr;
    tr.data  = data;
    tr.delay = 0;
    env.apb_drv.seq_item_port.put(tr);
  endtask

endclass : test_slave_transmit