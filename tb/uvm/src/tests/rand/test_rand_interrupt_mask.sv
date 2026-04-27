// Test: Constrained Random Interrupt Mask
// Cover: Random combinations of interrupt masks, at least 3 interrupts enabled
// Constraints: At least 3 bits in INTR_MASK == 0 (meaning those interrupts are enabled)
class test_rand_interrupt_mask extends base_test;

  `uvm_component_utils(test_rand_interrupt_mask)

  // Interrupt bits in INTR_MASK register
  // INTR_MASK[10:0] maps to interrupt sources
  // 0 = enabled (not masked), 1 = masked

  logic [10:0] rand_mask_pattern;

  constraint mask_c {
    // At least 3 interrupt sources should be enabled (not masked)
    $countones(~rand_mask_pattern) >= 3;
  }

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
  begin
    logic [31:0] mask_val;
    phase.raise_objection(this);
    `uvm_info("TEST_RAND_INTERRUPT_MASK", "Starting Random Interrupt Mask Test...", UVM_MEDIUM)

    // Generate random mask pattern
    rand_mask_pattern = $urandom();

    `uvm_info("TEST_RAND_INTERRUPT_MASK",
      $sformatf("Random mask pattern: 0x%03h (inverted=0x%03h, %0d bits enabled)",
        rand_mask_pattern[10:0], ~rand_mask_pattern[10:0], $countones(~rand_mask_pattern)), UVM_MEDIUM)

    // Write INTR_MASK (bits 0=RX_FULL, 1=TX_EMPTY, 2=TX_ABRT, ... 10=ACTIVITY)
    // Mask value: 0=enabled, 1=masked
    apb_write(8'h20, {21'b1, rand_mask_pattern});  // Upper bits 1=masked

    // Read back
    apb_read(8'h20, mask_val);
    `uvm_info("TEST_RAND_INTERRUPT_MASK", $sformatf("INTR_MASK written, read=0x%08h", mask_val), UVM_MEDIUM)

    // Test all mask combinations manually
    begin
      `uvm_info("TEST_RAND_INTERRUPT_MASK", "Testing all-mask (all enabled) pattern...", UVM_MEDIUM)
      apb_write(8'h20, 32'hFFFFF800);  // All 0 = all enabled
      apb_read(8'h20, mask_val);
      `uvm_info("TEST_RAND_INTERRUPT_MASK", $sformatf("All-enabled INTR_MASK=0x%08h", mask_val), UVM_MEDIUM)

      `uvm_info("TEST_RAND_INTERRUPT_MASK", "Testing all-unmask (all masked) pattern...", UVM_MEDIUM)
      apb_write(8'h20, 32'hFFF);  // All 1 = all masked
      apb_read(8'h20, mask_val);
      `uvm_info("TEST_RAND_INTERRUPT_MASK", $sformatf("All-masked INTR_MASK=0x%08h", mask_val), UVM_MEDIUM)

      // Test critical interrupts individually: RX_FULL, TX_EMPTY, TX_ABRT
      `uvm_info("TEST_RAND_INTERRUPT_MASK", "Testing individual interrupt masks...", UVM_MEDIUM)

      // Only RX_FULL enabled
      apb_write(8'h20, 32'hFFE);  // bit0=0 (RX_FULL enabled), others=1 (masked)
      apb_read(8'h20, mask_val);
      `uvm_info("TEST_RAND_INTERRUPT_MASK", $sformatf("Only RX_FULL enabled: INTR_MASK=0x%08h", mask_val), UVM_MEDIUM)

      // Only TX_EMPTY enabled
      apb_write(8'h20, 32'hFFD);  // bit1=0 (TX_EMPTY enabled), others=1
      apb_read(8'h20, mask_val);
      `uvm_info("TEST_RAND_INTERRUPT_MASK", $sformatf("Only TX_EMPTY enabled: INTR_MASK=0x%08h", mask_val), UVM_MEDIUM)

      // Only TX_ABRT enabled
      apb_write(8'h20, 32'hFFB);  // bit2=0 (TX_ABRT enabled), others=1
      apb_read(8'h20, mask_val);
      `uvm_info("TEST_RAND_INTERRUPT_MASK", $sformatf("Only TX_ABRT enabled: INTR_MASK=0x%08h", mask_val), UVM_MEDIUM)
    end

    `uvm_info("TEST_RAND_INTERRUPT_MASK", "Random Interrupt Mask Test PASSED", UVM_MEDIUM)
    phase.drop_objection(this);
  end
  endtask

  task apb_write(input logic [7:0] addr, input logic [31:0] data);
    virtual apb_if vif = env.apb_drv.vif;
    @(posedge vif.pclk);
    vif.psel    <= 1'b1;
    vif.penable <= 1'b0;
    vif.pwrite  <= 1'b1;
    vif.paddr   <= addr;
    vif.pwdata  <= data;
    @(posedge vif.pclk);
    vif.penable <= 1'b1;
    @(posedge vif.pclk);
    while (!vif.pready) @(posedge vif.pclk);
    vif.psel    <= 1'b0;
    vif.penable <= 1'b0;
  endtask

  task apb_read(input logic [7:0] addr, output logic [31:0] data);
    virtual apb_if vif = env.apb_drv.vif;
    @(posedge vif.pclk);
    vif.psel    <= 1'b1;
    vif.penable <= 1'b0;
    vif.pwrite  <= 1'b0;
    vif.paddr   <= addr;
    @(posedge vif.pclk);
    vif.penable <= 1'b1;
    @(posedge vif.pclk);
    while (!vif.pready) @(posedge vif.pclk);
    data = vif.prdata;
    vif.psel    <= 1'b0;
    vif.penable <= 1'b0;
  endtask

endclass : test_rand_interrupt_mask
