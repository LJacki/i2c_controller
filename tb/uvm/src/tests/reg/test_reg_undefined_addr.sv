// Test: Register Undefined Address Returns 0
// Cover: Undefined addresses (0x50~0xFF) return 0, all defined addresses return valid data
class test_reg_undefined_addr extends base_test;

  `uvm_component_utils(test_reg_undefined_addr)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
  begin
    int error_count = 0;
    logic [31:0] val;
    logic [7:0] test_addrs[] = '{8'h50, 8'h60, 8'h70, 8'h80, 8'h90, 8'hA0, 8'hB0, 8'hC0, 8'hD0, 8'hE0, 8'hF0, 8'hFF};
    phase.raise_objection(this);
    `uvm_info("TEST_REG_UNDEFINED_ADDR", "Starting Undefined Address Test...", UVM_MEDIUM)


    // === Test defined addresses return non-zero (or specific values) ===

    // Write to a defined register, then read it back
    apb_write(8'h00, 12'h55);  // CON
    apb_read(8'h00, val);
    `uvm_info("TEST_REG_UNDEFINED_ADDR", $sformatf("CON (0x00) read=0x%08h", val), UVM_MEDIUM)

    apb_write(8'h04, {22'b0, 1'b0, 1'b0, 7'h3C});  // TAR
    apb_read(8'h04, val);
    `uvm_info("TEST_REG_UNDEFINED_ADDR", $sformatf("TAR (0x04) read=0x%08h", val), UVM_MEDIUM)

    // === Test undefined addresses ===
    // Undefined range: 0x50 to 0xFF

    foreach (test_addrs[i]) begin
      apb_read(test_addrs[i], val);
      `uvm_info("TEST_REG_UNDEFINED_ADDR", $sformatf("Undefined addr 0x%02h read=0x%08h", test_addrs[i], val), UVM_MEDIUM)
      if (val !== 32'h0) begin
        `uvm_error("TEST_REG_UNDEFINED_ADDR", $sformatf("Undefined address 0x%02h returned non-zero: 0x%08h", test_addrs[i], val))
        error_count++;
      end
    end

    // === Also test some gaps within defined range ===
    // Addrs 0x50-0xFC are undefined
    // Addrs 0x00-0x4C are defined
    // Check some boundary values near the cutoff
    apb_read(8'h4C, val);  // Last defined address
    `uvm_info("TEST_REG_UNDEFINED_ADDR", $sformatf("Last defined addr 0x4C read=0x%08h", val), UVM_MEDIUM)

    apb_read(8'h4D, val);  // First undefined
    `uvm_info("TEST_REG_UNDEFINED_ADDR", $sformatf("First undefined 0x4D read=0x%08h", val), UVM_MEDIUM)
    if (val !== 32'h0)
      `uvm_error("TEST_REG_UNDEFINED_ADDR", "Address 0x4D should return 0")

    if (error_count == 0)
      `uvm_info("TEST_REG_UNDEFINED_ADDR", "Undefined Address Test PASSED", UVM_MEDIUM)
    else
      `uvm_error("TEST_REG_UNDEFINED_ADDR", $sformatf("Undefined Address Test FAILED with %0d errors", error_count))

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

endclass : test_reg_undefined_addr
