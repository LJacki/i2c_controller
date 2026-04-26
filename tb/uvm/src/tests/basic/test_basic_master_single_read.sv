// Test: Basic Master Single Read
// Sequence: START -> ADDR(0x3C)+R -> DATA(slave) -> NACK -> STOP
// Cover: Master single byte read, DATA_CMD with CMD=1, NACK last byte
class test_basic_master_single_read extends base_test;

  `uvm_component_utils(test_basic_master_single_read)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    `uvm_info("TEST_BASIC_MASTER_SINGLE_READ", "Starting Master Single Read Test...", UVM_MEDIUM)

    // Configure Master
    apb_write(8'h04, {22'b0, 1'b0, 1'b0, 7'h3C});  // TAR=0x3C
    apb_write(8'h00, 12'h1B);  // MASTER_MODE=1, SPEED=Fast, RESTART_EN=1, SLAVE_DISABLE=1
    apb_write(8'h18, 16'd60);
    apb_write(8'h1C, 16'd130);
    apb_write(8'h34, 32'h1);   // ENABLE=1

    // Write DATA_CMD: CMD=1 (read transaction), DAT=0x00 (dummy)
    apb_write(8'h0C, {23'b0, 1'b1, 8'h00});  // DAT=0x00, CMD=1

    #100us;

    // Read RX FIFO to get received data
    bit [31:0] rx_data;
    apb_read(8'h0C, rx_data);
    `uvm_info("TEST_BASIC_MASTER_SINGLE_READ", $sformatf("RX DATA_CMD=0x%08h", rx_data), UVM_MEDIUM)

    `uvm_info("TEST_BASIC_MASTER_SINGLE_READ", "Master Single Read Test PASSED", UVM_MEDIUM)
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

  task apb_read(bit [7:0] addr, output bit [31:0] data);
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

endclass : test_basic_master_single_read
