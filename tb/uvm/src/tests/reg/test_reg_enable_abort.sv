// Test: Register ENABLE and ABORT
// Cover: ENABLE register, dynamic enable/disable, ABORT bit, ENABLE_STATUS
class test_reg_enable_abort extends base_test;

  `uvm_component_utils(test_reg_enable_abort)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
  begin
    logic [31:0] en_val;
    logic [31:0] en_stat;
    phase.raise_objection(this);
    `uvm_info("TEST_REG_ENABLE_ABORT", "Starting ENABLE/ABORT Register Test...", UVM_MEDIUM)

    // Read initial ENABLE status (should be 0 after reset)
    apb_read(8'h34, en_val);
    `uvm_info("TEST_REG_ENABLE_ABORT", $sformatf("ENABLE initial=0x%08h", en_val), UVM_MEDIUM)
    if (en_val[0] !== 1'b0)
      `uvm_error("TEST_REG_ENABLE_ABORT", "ENABLE should be 0 after reset")

    // Read ENABLE_STATUS (RO) to check IC_EN
    apb_read(8'h4C, en_stat);
    `uvm_info("TEST_REG_ENABLE_ABORT", $sformatf("ENABLE_STATUS initial=0x%08h", en_stat), UVM_MEDIUM)

    // Enable I2C controller
    apb_write(8'h34, 32'h1);  // ENABLE=1
    apb_read(8'h34, en_val);
    `uvm_info("TEST_REG_ENABLE_ABORT", $sformatf("ENABLE after set=1: 0x%08h", en_val), UVM_MEDIUM)
    if (en_val[0] !== 1'b1)
      `uvm_error("TEST_REG_ENABLE_ABORT", "ENABLE bit not set")

    // Configure and do a transaction while enabled
    apb_write(8'h04, {22'b0, 1'b0, 1'b0, 7'h3C});
    apb_write(8'h00, 12'h1B);
    apb_write(8'h18, 16'd60);
    apb_write(8'h1C, 16'd130);
    apb_write(8'h0C, {24'b0, 8'h99});

    #20us;

    // Check ENABLE_STATUS while active
    apb_read(8'h4C, en_stat);
    `uvm_info("TEST_REG_ENABLE_ABORT", $sformatf("ENABLE_STATUS while active=0x%08h", en_stat), UVM_MEDIUM)

    // Test ABORT: set ABORT=1 to stop current transaction
    apb_write(8'h34, 32'h3);  // ENABLE=1, ABORT=1
    #10us;

    // ABORT should self-clear after transaction stops
    apb_read(8'h34, en_val);
    `uvm_info("TEST_REG_ENABLE_ABORT", $sformatf("ENABLE after ABORT=1: 0x%08h", en_val), UVM_MEDIUM)

    // Disable controller
    apb_write(8'h34, 32'h0);  // ENABLE=0
    apb_read(8'h34, en_val);
    if (en_val[0] !== 1'b0)
      `uvm_error("TEST_REG_ENABLE_ABORT", "ENABLE should be 0 after disable")

    // Read ENABLE_STATUS after disable
    apb_read(8'h4C, en_stat);
    `uvm_info("TEST_REG_ENABLE_ABORT", $sformatf("ENABLE_STATUS after disable=0x%08h", en_stat), UVM_MEDIUM)

    `uvm_info("TEST_REG_ENABLE_ABORT", "ENABLE/ABORT Register Test PASSED", UVM_MEDIUM)
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

endclass : test_reg_enable_abort
