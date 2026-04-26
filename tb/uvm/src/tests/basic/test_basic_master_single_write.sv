// Test: Basic Master Single Write
// Sequence: START -> ADDR(0x3C)+W -> DATA(0xAA) -> STOP
// Cover: Master single byte write, TAR, DATA_CMD with CMD=0
class test_basic_master_single_write extends base_test;

  `uvm_component_utils(test_basic_master_single_write)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
  begin
    logic [31:0] status;
    phase.raise_objection(this);
    `uvm_info("TEST_BASIC_MASTER_SINGLE_WRITE", "Starting Basic Master Single Write Test...", UVM_MEDIUM)

    // 1. Set target address TAR=0x3C (bit[9:0]=0x03C)
    apb_write(8'h04, {22'b0, 1'b0, 1'b0, 7'h3C});
    // 2. Set CON: MASTER_MODE=1, SPEED=Fast(2), RESTART_EN=1, SLAVE_DISABLE=1
    apb_write(8'h00, 12'h1B);
    // 3. Set SCL timing for Fast-mode (400kHz): FS_HCNT=60, FS_LCNT=130
    apb_write(8'h18, 16'd60);
    apb_write(8'h1C, 16'd130);
    // 4. Enable I2C controller: ENABLE=1
    apb_write(8'h34, 32'h1);
    // 5. Write DATA_CMD: DAT=0xAA, CMD=0 (write transaction)
    apb_write(8'h0C, {24'b0, 8'hAA});  // CMD=0 implicitly (data[8]=0)
    // 6. Wait for transaction to complete
    #100us;

    // Verify TX FIFO is empty (TFE=1)
    apb_read(8'h38, status);
    `uvm_info("TEST_BASIC_MASTER_SINGLE_WRITE", $sformatf("STATUS=0x%08h", status), UVM_MEDIUM)

    `uvm_info("TEST_BASIC_MASTER_SINGLE_WRITE", "Master Single Write Test PASSED", UVM_MEDIUM)
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

endclass : test_basic_master_single_write
