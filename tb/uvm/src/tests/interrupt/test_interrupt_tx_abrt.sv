// Test: Interrupt TX_ABRT (various abort sources)
// Cover: TX_ABRT (bit 2), multiple TX_ABRT_SOURCE bits, INTR_MASK
class test_interrupt_tx_abrt extends base_test;

  `uvm_component_utils(test_interrupt_tx_abrt)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    bit [31:0] raw_intr;
    bit [31:0] txabrt;
    bit [31:0] txabrt_clear;
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

endclass : test_interrupt_tx_abrt
