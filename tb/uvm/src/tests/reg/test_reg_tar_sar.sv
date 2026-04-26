// Test: Register TAR and SAR
// Cover: TAR (target address), SAR (slave address), GC_OR_START, boundary addresses
class test_reg_tar_sar extends base_test;

  `uvm_component_utils(test_reg_tar_sar)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
  begin
    logic [31:0] tar_val;
    logic [31:0] sar_val;
    phase.raise_objection(this);
    `uvm_info("TEST_REG_TAR_SAR", "Starting TAR/SAR Register Test...", UVM_MEDIUM)

    // === TAR Tests ===
    // TAR[9:0] = target address, TAR[10]=GC_OR_START, TAR[11]=SPECIAL

    // Test TAR with normal address
    apb_write(8'h04, {22'b0, 1'b0, 1'b0, 7'h3C});  // TAR=0x3C
    apb_read(8'h04, tar_val);
    `uvm_info("TEST_REG_TAR_SAR", $sformatf("TAR=0x3C: read=0x%08h", tar_val), UVM_MEDIUM)
    if (tar_val[6:0] !== 7'h3C)
      `uvm_error("TEST_REG_TAR_SAR", "TAR[6:0] mismatch")

    // Test TAR boundary: address 0x00 (lowest)
    apb_write(8'h04, {22'b0, 1'b0, 1'b0, 7'h00});  // TAR=0x00
    apb_read(8'h04, tar_val);
    `uvm_info("TEST_REG_TAR_SAR", $sformatf("TAR=0x00: read=0x%08h", tar_val), UVM_MEDIUM)
    if (tar_val[6:0] !== 7'h00)
      `uvm_error("TEST_REG_TAR_SAR", "TAR[6:0] should be 0x00")

    // Test TAR boundary: address 0x7F (highest 7-bit)
    apb_write(8'h04, {22'b0, 1'b0, 1'b0, 7'h7F});  // TAR=0x7F
    apb_read(8'h04, tar_val);
    `uvm_info("TEST_REG_TAR_SAR", $sformatf("TAR=0x7F: read=0x%08h", tar_val), UVM_MEDIUM)
    if (tar_val[6:0] !== 7'h7F)
      `uvm_error("TEST_REG_TAR_SAR", "TAR[6:0] should be 0x7F")

    // === SAR Tests ===
    // SAR[6:0] = slave address

    // Test SAR with normal address
    apb_write(8'h08, {25'b0, 7'h3C});  // SAR=0x3C
    apb_read(8'h08, sar_val);
    `uvm_info("TEST_REG_TAR_SAR", $sformatf("SAR=0x3C: read=0x%08h", sar_val), UVM_MEDIUM)
    if (sar_val[6:0] !== 7'h3C)
      `uvm_error("TEST_REG_TAR_SAR", "SAR[6:0] mismatch")

    // Test SAR boundary: 0x00
    apb_write(8'h08, {25'b0, 7'h00});
    apb_read(8'h08, sar_val);
    if (sar_val[6:0] !== 7'h00)
      `uvm_error("TEST_REG_TAR_SAR", "SAR[6:0] should be 0x00")

    // Test SAR boundary: 0x7F
    apb_write(8'h08, {25'b0, 7'h7F});
    apb_read(8'h08, sar_val);
    if (sar_val[6:0] !== 7'h7F)
      `uvm_error("TEST_REG_TAR_SAR", "SAR[6:0] should be 0x7F")

    // Test GC_OR_START and SPECIAL bits
    apb_write(8'h04, {20'b0, 1'b1, 1'b1, 7'h00});  // SPECIAL=1, GC_OR_START=1
    apb_read(8'h04, tar_val);
    `uvm_info("TEST_REG_TAR_SAR", $sformatf("TAR SPECIAL+GC: read=0x%08h", tar_val), UVM_MEDIUM)

    `uvm_info("TEST_REG_TAR_SAR", "TAR/SAR Register Test PASSED", UVM_MEDIUM)
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

endclass : test_reg_tar_sar
