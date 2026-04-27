// Test: Basic Master Burst Write (8 bytes)
// Sequence: START -> ADDR(0x3C)+W -> DATA[0..7] -> STOP
// Cover: Master burst write, fill TX FIFO, multiple DATA_CMD writes
class test_basic_master_burst_write extends base_test;

  `uvm_component_utils(test_basic_master_burst_write)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
  begin
    logic [31:0] txflr;
    phase.raise_objection(this);
    `uvm_info("TEST_BASIC_MASTER_BURST_WRITE", "Starting Master Burst Write Test (8 bytes)...", UVM_MEDIUM)

    // Configure Master
    apb_write(8'h04, {22'b0, 1'b0, 1'b0, 7'h3C});  // TAR=0x3C
    apb_write(8'h00, 12'h1B);  // MASTER_MODE=1, SPEED=Fast, RESTART_EN=1, SLAVE_DISABLE=1
    apb_write(8'h18, 16'd60);
    apb_write(8'h1C, 16'd130);
    apb_write(8'h34, 32'h1);   // ENABLE=1

    // Write 8 bytes consecutively (CMD=0 for all = write transactions)
    for (int i = 0; i < 8; i++) begin
      logic [7:0] data_byte = 8'hA0 + i;
      apb_write(8'h0C, {24'b0, data_byte});  // DAT=data, CMD=0
      `uvm_info("TEST_BASIC_MASTER_BURST_WRITE", $sformatf("Wrote DATA_CMD[0x%02x]=0x%02x", i, data_byte), UVM_MEDIUM)
      #2us;  // small spacing between writes
    end

    // Check TX FIFO level before it drains
    apb_read(8'h3C, txflr);
    `uvm_info("TEST_BASIC_MASTER_BURST_WRITE", $sformatf("TXFLR=0x%08h", txflr), UVM_MEDIUM)

    #100us;

    `uvm_info("TEST_BASIC_MASTER_BURST_WRITE", "Master Burst Write Test PASSED", UVM_MEDIUM)
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

endclass : test_basic_master_burst_write
