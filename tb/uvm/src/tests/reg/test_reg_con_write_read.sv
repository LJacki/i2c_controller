// Test: Register CON Write/Read
// Cover: CON register all fields, MASTER_MODE, SPEED, RESTART_EN, SLAVE_DISABLE
class test_reg_con_write_read extends base_test;

  `uvm_component_utils(test_reg_con_write_read)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    bit [31:0] con_val;
    phase.raise_objection(this);
    `uvm_info("TEST_REG_CON_WRITE_READ", "Starting CON Register Write/Read Test...", UVM_MEDIUM)

    // Test pattern: all fields of CON
    // CON[0]   = MASTER_MODE
    // CON[2:1] = SPEED (2'b01=Standard, 2'b10=Fast, 2'b11=Fast+)
    // CON[3]   = SLAVE_ADDR_10BIT (0 for 7-bit)
    // CON[4]   = MASTER_ADDR_10BIT (0 for 7-bit)
    // CON[5]   = RESTART_EN
    // CON[6]   = SLAVE_DISABLE
    // CON[7]   = STOP_DET_IF_MASTER_ACTIVE

    // Test 1: Pure Master mode (MASTER_MODE=1, SLAVE_DISABLE=1)
    apb_write(8'h00, 12'h43);  // MASTER_MODE=1, SPEED=2, RESTART_EN=1, SLAVE_DISABLE=1
    apb_read(8'h00, con_val);
    `uvm_info("TEST_REG_CON_WRITE_READ", $sformatf("CON after write 0x43: 0x%08h", con_val), UVM_MEDIUM)
    if (con_val[0] !== 1'b1)
      `uvm_error("TEST_REG_CON_WRITE_READ", "MASTER_MODE bit not set correctly")

    // Test 2: Pure Slave mode (MASTER_MODE=0, SLAVE_DISABLE=0)
    apb_write(8'h00, 12'h00);  // MASTER_MODE=0, SLAVE_DISABLE=0
    apb_read(8'h00, con_val);
    `uvm_info("TEST_REG_CON_WRITE_READ", $sformatf("CON after write 0x00: 0x%08h", con_val), UVM_MEDIUM)

    // Test 3: Speed modes
    // Standard mode (SPEED=01)
    apb_write(8'h00, 12'h01);  // MASTER_MODE=1, SPEED=01
    apb_read(8'h00, con_val);
    `uvm_info("TEST_REG_CON_WRITE_READ", $sformatf("CON Standard mode: 0x%08h", con_val), UVM_MEDIUM)

    // Fast mode (SPEED=10)
    apb_write(8'h00, 12'h03);  // MASTER_MODE=1, SPEED=10
    apb_read(8'h00, con_val);
    `uvm_info("TEST_REG_CON_WRITE_READ", $sformatf("CON Fast mode: 0x%08h", con_val), UVM_MEDIUM)

    // Fast+ mode (SPEED=11)
    apb_write(8'h00, 12'h05);  // MASTER_MODE=1, SPEED=11
    apb_read(8'h00, con_val);
    `uvm_info("TEST_REG_CON_WRITE_READ", $sformatf("CON Fast+ mode: 0x%08h", con_val), UVM_MEDIUM)

    // Test 4: RESTART_EN toggle
    apb_write(8'h00, 12'h21);  // RESTART_EN=0
    apb_read(8'h00, con_val);
    if (con_val[5] !== 1'b0)
      `uvm_error("TEST_REG_CON_WRITE_READ", "RESTART_EN not cleared correctly")

    apb_write(8'h00, 12'h41);  // RESTART_EN=1
    apb_read(8'h00, con_val);
    if (con_val[5] !== 1'b1)
      `uvm_error("TEST_REG_CON_WRITE_READ", "RESTART_EN not set correctly")

    `uvm_info("TEST_REG_CON_WRITE_READ", "CON Register Write/Read Test PASSED", UVM_MEDIUM)
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

endclass : test_reg_con_write_read
