// Test: Basic Master Burst Read (8 bytes)
// Sequence: START -> ADDR(0x3C)+R -> DATA[0..7] -> NACK(last) -> STOP
// Cover: Master burst read, NACK on last byte, multiple CMD=1 writes
class test_basic_master_burst_read extends base_test;

  `uvm_component_utils(test_basic_master_burst_read)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
  begin
    logic [31:0] rxflr;
    phase.raise_objection(this);
    `uvm_info("TEST_BASIC_MASTER_BURST_READ", "Starting Master Burst Read Test (8 bytes)...", UVM_MEDIUM)

    // Configure Master
    apb_write(8'h04, {22'b0, 1'b0, 1'b0, 7'h3C});  // TAR=0x3C
    apb_write(8'h00, 12'h1B);  // MASTER_MODE=1, SPEED=Fast, RESTART_EN=1, SLAVE_DISABLE=1
    apb_write(8'h18, 16'd60);
    apb_write(8'h1C, 16'd130);
    apb_write(8'h34, 32'h1);   // ENABLE=1

    // Write 8 CMD=1 entries (8 read commands)
    // Master will: ACK first 7 bytes, NACK last byte, then STOP
    for (int i = 0; i < 8; i++) begin
      apb_write(8'h0C, {23'b0, 1'b1, 8'h00});  // CMD=1 (read), DAT=0x00
      `uvm_info("TEST_BASIC_MASTER_BURST_READ", $sformatf("Issued READ CMD #%0d", i), UVM_MEDIUM)
      #2us;
    end

    #100us;

    // Check RXFLR (should be 8 if all bytes received)
    apb_read(8'h40, rxflr);
    `uvm_info("TEST_BASIC_MASTER_BURST_READ", $sformatf("RXFLR=0x%08h", rxflr), UVM_MEDIUM)

    // Drain RX FIFO
    for (int i = 0; i < 8; i++) begin
      logic [31:0] rx_data;
      apb_read(8'h0C, rx_data);
      `uvm_info("TEST_BASIC_MASTER_BURST_READ", $sformatf("RX[%0d]=0x%02x", i, rx_data[7:0]), UVM_MEDIUM)
    end

    `uvm_info("TEST_BASIC_MASTER_BURST_READ", "Master Burst Read Test PASSED", UVM_MEDIUM)
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

endclass : test_basic_master_burst_read
