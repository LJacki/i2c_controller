// Test: Master Single Write
// Sequence: START -> ADDR(0x3C)+W -> DATA(0xAA) -> STOP
class test_master_single_write extends base_test;

  `uvm_component_utils(test_master_single_write)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    `uvm_info("TEST_MASTER_SINGLE_WRITE", "Starting Master Single Write Test...", UVM_MEDIUM)

    // Configuration sequence via APB
    // 1. Set target address (TAR = 0x3C)
    apb_write(8'h04, {22'b0, 1'b0, 1'b0, 7'h3C});
    // 2. Set control: MASTER_MODE=1, SPEED=Fast(2), RESTART_EN=1, SLAVE_DISABLE=1
    apb_write(8'h00, 12'h1B);  // MASTER_MODE=1, SPEED=2, RESTART_EN=1, SLAVE_DISABLE=1
    // 3. Set SCL timing (Fast mode: HCNT=60, LCNT=130)
    apb_write(8'h18, 16'd60);   // FS_SCL_HCNT
    apb_write(8'h1C, 16'd130);  // FS_SCL_LCNT
    // 4. Enable I2C controller
    apb_write(8'h30, 32'h1);   // ENABLE=1
    // 5. Write DATA_CMD: DAT=0xAA, CMD=0 (write)
    apb_write(8'h0C, {24'b0, 8'hAA});  // Write 0xAA with CMD=0
    // 6. Wait for transaction to complete
    #50us;

    `uvm_info("TEST_MASTER_SINGLE_WRITE", "Master Single Write Test Completed", UVM_MEDIUM)
    phase.drop_objection(this);
  endtask

  // Helper tasks for APB operations
  task apb_write(bit [7:0] addr, bit [31:0] data);
    apb_transfer tr;
    tr = apb_transfer::type_id::create("tr");
    tr.kind  = apb_transfer::APB_WRITE;
    tr.addr  = addr;
    tr.data  = data;
    tr.delay = 0;
    env.apb_drv.seq_item_port.put(tr);
  endtask

endclass : test_master_single_write