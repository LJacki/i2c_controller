// Test: Interrupt TX_ABRT (various abort sources)
// Cover: TX_ABRT (bit 2), multiple TX_ABRT_SOURCE bits, INTR_MASK
class test_interrupt_tx_abrt extends base_test;

  `uvm_component_utils(test_interrupt_tx_abrt)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
  begin
    logic [31:0] raw_intr;
    logic [31:0] txabrt;
    logic [31:0] txabrt_clear;
    phase.raise_objection(this);
    `uvm_info("TEST_INTERRUPT_TX_ABRT", "Starting TX_ABRT Interrupt Test...", UVM_MEDIUM)

    // Unmask TX_ABRT interrupt (INTR_MASK[2] = 0 -> enabled)
    apb_write(8'h20, 32'hFFB);  // Mask all except bit 2 (M_TX_ABRT=0 -> enabled)

    // Set target address that has no slave (will cause ABRT_7B_NOACK)
    apb_write(8'h04, {22'b0, 1'b0, 1'b0, 7'h7F});  // TAR=0x7F (no slave)
    apb_write(8'h00, 12'h1B);  // MASTER_MODE=1, SPEED=Fast, RESTART_EN=1, SLAVE_DISABLE=1
    apb_write(8'h18, 16'd60);
    apb_write(8'h1C, 16'd130);
    apb_write(8'h34, 32'h1);   // ENABLE=1

    // Try to write to non-responsive slave
    apb_write(8'h0C, {24'b0, 8'hAA});

    #50us;

    // Check RAW_INTR_STAT bit 2 (R_TX_ABRT)
    apb_read(8'h28, raw_intr);
    `uvm_info("TEST_INTERRUPT_TX_ABRT", $sformatf("RAW_INTR_STAT=0x%08h (bit2=TX_ABRT)", raw_intr), UVM_MEDIUM)

    // Read TX_ABRT_SOURCE to check abort source bits
    apb_read(8'h48, txabrt);
    `uvm_info("TEST_INTERRUPT_TX_ABRT", $sformatf("TX_ABRT_SOURCE=0x%08h", txabrt), UVM_MEDIUM)

    // Report which abort bits are set
    if (txabrt[0]) `uvm_info("TEST_INTERRUPT_TX_ABRT", "ABRT_7B_NOACK (bit0) is SET", UVM_MEDIUM)
    if (txabrt[3]) `uvm_info("TEST_INTERRUPT_TX_ABRT", "ABRT_TXDATA_NOACK (bit3) is SET", UVM_MEDIUM)
    if (txabrt[12]) `uvm_info("TEST_INTERRUPT_TX_ABRT", "ABRT_ARB_LOST (bit12) is SET", UVM_MEDIUM)
    if (txabrt[15]) `uvm_info("TEST_INTERRUPT_TX_ABRT", "ABRT_SLVRD_INTXFR (bit15) is SET", UVM_MEDIUM)

    // Clear TX_ABRT by reading TX_ABRT_SOURCE (clr-on-read behavior)
    apb_read(8'h48, txabrt_clear);
    `uvm_info("TEST_INTERRUPT_TX_ABRT", $sformatf("TX_ABRT cleared (read back)=0x%08h", txabrt_clear), UVM_MEDIUM)

    `uvm_info("TEST_INTERRUPT_TX_ABRT", "TX_ABRT interrupt test completed", UVM_MEDIUM)
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

endclass : test_interrupt_tx_abrt
