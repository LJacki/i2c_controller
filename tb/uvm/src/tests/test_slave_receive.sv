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
        i2c_transfer tr;
        tr = i2c_transfer::type_id::create("tr");
        tr.kind = i2c_transfer::I2C_WRITE;
        tr.addr = 7'h3C;
        tr.data = '{8'hBB};
        tr.last_cmd = 1'b0;
        env.i2c_master.seq_item_port.put(tr);
      end
    join

    #50us;

    `uvm_info("TEST_SLAVE_RECEIVE", "Slave Receive Test Completed", UVM_MEDIUM)
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

endclass : test_slave_receive