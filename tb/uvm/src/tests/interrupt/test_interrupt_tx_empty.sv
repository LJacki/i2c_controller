// Test: Interrupt TX_EMPTY
// Cover: TX_EMPTY (bit 1), TX_TL threshold, TXFLR
class test_interrupt_tx_empty extends base_test;

  `uvm_component_utils(test_interrupt_tx_empty)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
  begin
    logic [31:0] raw_intr;
    logic [31:0] txflr;
    logic [31:0] intr_stat;
    phase.raise_objection(this);
    `uvm_info("TEST_INTERRUPT_TX_EMPTY", "Starting TX_EMPTY Interrupt Test...", UVM_MEDIUM)

    // Unmask TX_EMPTY interrupt (INTR_MASK[1] = 0 -> enabled)
    apb_write(8'h20, 32'hFFD);  // Mask all except bit 1 (M_TX_EMPTY=0 -> enabled)

    // Set TX_TL = 0 (TX FIFO <= 0 triggers TX_EMPTY, i.e., when empty)
    apb_write(8'h30, 32'h0);  // TX_TL=0

    // Configure Master
    apb_write(8'h04, {22'b0, 1'b0, 1'b0, 7'h3C});
    apb_write(8'h00, 12'h1B);
    apb_write(8'h18, 16'd60);
    apb_write(8'h1C, 16'd130);
    apb_write(8'h34, 32'h1);   // ENABLE=1

    // Write single byte, wait for it to drain from TX FIFO
    apb_write(8'h0C, {24'b0, 8'h55});

    // Wait for TX FIFO to drain and trigger TX_EMPTY
    #100us;

    // Check RAW_INTR_STAT bit 1 (R_TX_EMPTY)
    apb_read(8'h28, raw_intr);
    `uvm_info("TEST_INTERRUPT_TX_EMPTY", $sformatf("RAW_INTR_STAT=0x%08h", raw_intr), UVM_MEDIUM)

    // Check TXFLR (should be 0 if empty)
    apb_read(8'h3C, txflr);
    `uvm_info("TEST_INTERRUPT_TX_EMPTY", $sformatf("TXFLR=0x%08h", txflr), UVM_MEDIUM)

    // Check INTR_STAT bit 1 (I_TX_EMPTY, post-mask)
    apb_read(8'h24, intr_stat);
    `uvm_info("TEST_INTERRUPT_TX_EMPTY", $sformatf("INTR_STAT=0x%08h", intr_stat), UVM_MEDIUM)

    `uvm_info("TEST_INTERRUPT_TX_EMPTY", "TX_EMPTY interrupt test completed", UVM_MEDIUM)
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

endclass : test_interrupt_tx_empty
