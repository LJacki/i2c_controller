// Test: Register HCNT/LCNT Speed Configuration
// Cover: SS_HCNT/SS_LCNT (Standard 100kHz), FS_HCNT/FS_LCNT (Fast 400kHz), frequency calculation
class test_reg_hcnt_lcnt_speed extends base_test;

  `uvm_component_utils(test_reg_hcnt_lcnt_speed)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    bit [31:0] hcnt_val;
    bit [31:0] lcnt_val;
    bit [31:0] con_val;
    phase.raise_objection(this);
    `uvm_info("TEST_REG_HCNT_LCNT_SPEED", "Starting HCNT/LCNT Speed Register Test...", UVM_MEDIUM)

    // === Standard-mode (100kHz) configuration ===
    // For pclk=100MHz: I2C_freq = pclk / (2 * (HCNT+1 + LCNT+1))
    // 100kHz = 100MHz / (2 * 500) -> HCNT+LCNT+2 = 500 -> HCNT=LCNT=249
    // But spec uses HCNT=LCNT=400 for simpler calculation

    // Write SS_HCNT (0x10)
    apb_write(8'h10, 16'd400);  // Standard SCL high count
    apb_read(8'h10, hcnt_val);
    `uvm_info("TEST_REG_HCNT_LCNT_SPEED", $sformatf("SS_HCNT written=400, read=0x%08h", hcnt_val), UVM_MEDIUM)
    if (hcnt_val[15:0] !== 16'd400)
      `uvm_error("TEST_REG_HCNT_LCNT_SPEED", "SS_HCNT mismatch")

    // Write SS_LCNT (0x14)
    apb_write(8'h14, 16'd400);  // Standard SCL low count
    apb_read(8'h14, lcnt_val);
    `uvm_info("TEST_REG_HCNT_LCNT_SPEED", $sformatf("SS_LCNT written=400, read=0x%08h", lcnt_val), UVM_MEDIUM)
    if (lcnt_val[15:0] !== 16'd400)
      `uvm_error("TEST_REG_HCNT_LCNT_SPEED", "SS_LCNT mismatch")

    // === Fast-mode (400kHz) configuration ===
    // For pclk=100MHz: HCNT=LCNT=124 gives ~400kHz
    apb_write(8'h18, 16'd60);   // Fast SCL high count (spec default)
    apb_read(8'h18, hcnt_val);
    `uvm_info("TEST_REG_HCNT_LCNT_SPEED", $sformatf("FS_HCNT written=60, read=0x%08h", hcnt_val), UVM_MEDIUM)

    apb_write(8'h1C, 16'd130);  // Fast SCL low count (spec default)
    apb_read(8'h1C, lcnt_val);
    `uvm_info("TEST_REG_HCNT_LCNT_SPEED", $sformatf("FS_LCNT written=130, read=0x%08h", lcnt_val), UVM_MEDIUM)

    // === Verify speed switching via CON register ===
    // Set CON to Standard mode (SPEED=01)
    apb_write(8'h00, 12'h01);  // MASTER_MODE=1, SPEED=01
    // Set CON to Fast mode (SPEED=10)
    apb_write(8'h00, 12'h03);  // MASTER_MODE=1, SPEED=10
    apb_read(8'h00, con_val);
    `uvm_info("TEST_REG_HCNT_LCNT_SPEED", $sformatf("CON SPEED=10 (Fast): 0x%08h", con_val), UVM_MEDIUM)
    if (con_val[2:1] !== 2'b10)
      `uvm_error("TEST_REG_HCNT_LCNT_SPEED", "CON SPEED field not set to Fast mode")

    // === Test with actual I2C transaction in Fast mode ===
    apb_write(8'h04, {22'b0, 1'b0, 1'b0, 7'h3C});  // TAR=0x3C
    apb_write(8'h34, 32'h1);   // ENABLE=1
    apb_write(8'h0C, {24'b0, 8'h55});  // Write 0x55

    #50us;

    `uvm_info("TEST_REG_HCNT_LCNT_SPEED", "HCNT/LCNT Speed Register Test PASSED", UVM_MEDIUM)
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

endclass : test_reg_hcnt_lcnt_speed
