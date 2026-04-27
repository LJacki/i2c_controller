// Test: Master Single Read
// Sequence: START -> ADDR(0x3C)+R -> DATA(internal) -> NACK -> STOP
class test_master_single_read extends base_test;

  `uvm_component_utils(test_master_single_read)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    `uvm_info("TEST_MASTER_SINGLE_READ", "Starting Master Single Read Test...", UVM_MEDIUM)

    // Configuration sequence via APB
    apb_write(8'h04, {22'b0, 1'b0, 1'b0, 7'h3C});
    apb_write(8'h00, 12'h1B);  // MASTER_MODE=1, SPEED=Fast, RESTART_EN=1, SLAVE_DISABLE=1
    apb_write(8'h18, 16'd60);
    apb_write(8'h1C, 16'd130);
    apb_write(8'h30, 32'h1);    // ENABLE=1
    apb_write(8'h0C, {24'b0, 8'h00, 1'b1});  // CMD=1 (read), DAT=0x00

    #50us;

    `uvm_info("TEST_MASTER_SINGLE_READ", "Master Single Read Test Completed", UVM_MEDIUM)
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

endclass : test_master_single_read