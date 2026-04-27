// Test: Master Burst Write (8 bytes)
// Sequence: START -> ADDR(0x3C)+W -> DATA[0..7] -> STOP
class test_master_burst_write extends base_test;

  `uvm_component_utils(test_master_burst_write)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    `uvm_info("TEST_MASTER_BURST_WRITE", "Starting Master Burst Write Test (8 bytes)...", UVM_MEDIUM)

    apb_write(8'h04, {22'b0, 1'b0, 1'b0, 7'h3C});
    apb_write(8'h00, 12'h1B);
    apb_write(8'h18, 16'd60);
    apb_write(8'h1C, 16'd130);
    apb_write(8'h30, 32'h1);

    // Write 8 bytes (CMD=0 for each)
    for (int i = 0; i < 8; i++) begin
      bit [7:0] data_byte = 8'hA0 + i;
      apb_write(8'h0C, {24'b0, data_byte});
      #5us;  // small delay between writes
    end

    #100us;

    `uvm_info("TEST_MASTER_BURST_WRITE", "Master Burst Write Test Completed", UVM_MEDIUM)
    phase.drop_objection(this);
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

endclass : test_master_burst_write