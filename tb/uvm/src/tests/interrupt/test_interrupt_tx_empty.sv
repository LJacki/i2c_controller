// Test: Interrupt TX_EMPTY
// Cover: TX_EMPTY (bit 1), TX_TL threshold, TXFLR
class test_interrupt_tx_empty extends base_test;

  `uvm_component_utils(test_interrupt_tx_empty)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
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
    bit [31:0] raw_intr;
    apb_read(8'h28, raw_intr);
    `uvm_info("TEST_INTERRUPT_TX_EMPTY", $sformatf("RAW_INTR_STAT=0x%08h", raw_intr), UVM_MEDIUM)

    // Check TXFLR (should be 0 if empty)
    bit [31:0] txflr;
    apb_read(8'h3C, txflr);
    `uvm_info("TEST_INTERRUPT_TX_EMPTY", $sformatf("TXFLR=0x%08h", txflr), UVM_MEDIUM)

    // Check INTR_STAT bit 1 (I_TX_EMPTY, post-mask)
    bit [31:0] intr_stat;
    apb_read(8'h24, intr_stat);
    `uvm_info("TEST_INTERRUPT_TX_EMPTY", $sformatf("INTR_STAT=0x%08h", intr_stat), UVM_MEDIUM)

    `uvm_info("TEST_INTERRUPT_TX_EMPTY", "TX_EMPTY interrupt test completed", UVM_MEDIUM)
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

endclass : test_interrupt_tx_empty
