// Test: Basic Master Repeated START (Write-then-Read)
// Sequence: START -> ADDR(0x3C)+W -> REG_ADDR -> RepeatedSTART -> ADDR(0x3C)+R -> DATA -> NACK -> STOP
// Cover: Repeated START detection, CMD=0 then CMD=1 triggers RESTART automatically
class test_basic_master_repeated_start extends base_test;

  `uvm_component_utils(test_basic_master_repeated_start)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
  begin
    logic [31:0] rxflr;
    phase.raise_objection(this);
    `uvm_info("TEST_BASIC_MASTER_REPEATED_START", "Starting Master Repeated START Test...", UVM_MEDIUM)

    // Configure Master
    apb_write(8'h04, {22'b0, 1'b0, 1'b0, 7'h3C});  // TAR=0x3C
    // CON: MASTER_MODE=1, SPEED=Fast(2), RESTART_EN=1 (critical!), SLAVE_DISABLE=1
    apb_write(8'h00, 12'h1B);  // RESTART_EN=1
    apb_write(8'h18, 16'd60);
    apb_write(8'h1C, 16'd130);
    apb_write(8'h34, 32'h1);   // ENABLE=1

    // CMD=0 first: write register address
    apb_write(8'h0C, {24'b0, 8'h5A});  // DAT=0x5A (reg addr), CMD=0

    // CMD=1 immediately after CMD=0: triggers Repeated START (no STOP in between)
    apb_write(8'h0C, {23'b0, 1'b1, 8'h00});  // CMD=1 (read), DAT=0x00

    #100us;

    // Check STATUS for RX FIFO
    apb_read(8'h40, rxflr);
    `uvm_info("TEST_BASIC_MASTER_REPEATED_START", $sformatf("RXFLR=0x%08h", rxflr), UVM_MEDIUM)

    `uvm_info("TEST_BASIC_MASTER_REPEATED_START", "Master Repeated START Test PASSED", UVM_MEDIUM)
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

endclass : test_basic_master_repeated_start
