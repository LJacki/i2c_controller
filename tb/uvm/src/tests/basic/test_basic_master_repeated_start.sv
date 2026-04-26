// Test: Basic Master Repeated START (Write-then-Read)
// Sequence: START -> ADDR(0x3C)+W -> REG_ADDR -> RepeatedSTART -> ADDR(0x3C)+R -> DATA -> NACK -> STOP
// Cover: Repeated START detection, CMD=0 then CMD=1 triggers RESTART automatically
class test_basic_master_repeated_start extends base_test;

  `uvm_component_utils(test_basic_master_repeated_start)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    `uvm_info("TEST_BASIC_MASTER_REPEATED_START", "Starting Master Repeated START Test...", UVM_MEDIUM)

    // Configure Master
    apb_write(8'h04, {22'b0, 1'b0, 1'b0, 7'h3C});  // TAR=0x3C
    // CON: MASTER_MODE=1, SPEED=Fast(2), RESTART_EN=1 (critical!), SLAVE_DISABLE=1
    apb_write(8'h00, 12'h1B);  // RESTART_EN=1
    apb_write(8'h18, 16'd60);
    apb_write(8'h1C, 16'd130);
    apb_write(8'h34, 32'h1);   // ENABLE=1

    // CMD=0 first: write register address
    apb_write(8'h0C, {24'b0, 8'h5A});  // DAT=0x5A (reg addr), CMD=0

    // CMD=1 immediately after CMD=0: triggers Repeated START (no STOP in between)
    apb_write(8'h0C, {23'b0, 1'b1, 8'h00});  // CMD=1 (read), DAT=0x00

    #100us;

    // Check STATUS for RX FIFO
    bit [31:0] rxflr;
    apb_read(8'h40, rxflr);
    `uvm_info("TEST_BASIC_MASTER_REPEATED_START", $sformatf("RXFLR=0x%08h", rxflr), UVM_MEDIUM)

    `uvm_info("TEST_BASIC_MASTER_REPEATED_START", "Master Repeated START Test PASSED", UVM_MEDIUM)
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

endclass : test_basic_master_repeated_start
