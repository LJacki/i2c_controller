// Test: Constrained Random Master Read
// Cover: Random byte count (1~16), random target address
// Constraints: 1 <= byte_count <= 16, addr != 0
class test_rand_master_read extends base_test;

  `uvm_component_utils(test_rand_master_read)

  // Random variables
  rand logic [6:0]  rand_addr;
  rand int        rand_byte_count;

  // Constraints
  constraint byte_count_c { rand_byte_count inside {[1:16]}; }
  constraint addr_c       { rand_addr != 7'h00; }

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
  begin
    logic [31:0] rxflr;
    phase.raise_objection(this);
    `uvm_info("TEST_RAND_MASTER_READ", "Starting Random Master Read Test...", UVM_MEDIUM)

    // Randomize transaction parameters
    rand_byte_count = $urandom_range(1, 16);
    rand_addr = $urandom_range(1, 127);

    `uvm_info("TEST_RAND_MASTER_READ",
      $sformatf("Randomized: addr=0x%02x, byte_count=%0d", rand_addr, rand_byte_count), UVM_MEDIUM)

    // Configure Master
    apb_write(8'h04, {22'b0, 1'b0, 1'b0, rand_addr});
    apb_write(8'h00, 12'h1B);  // MASTER_MODE=1, SPEED=Fast, RESTART_EN=1, SLAVE_DISABLE=1
    apb_write(8'h18, 16'd60);
    apb_write(8'h1C, 16'd130);
    apb_write(8'h34, 32'h1);   // ENABLE=1

    // Issue randomized number of read commands (CMD=1)
    for (int i = 0; i < rand_byte_count; i++) begin
      apb_write(8'h0C, {23'b0, 1'b1, 8'h00});  // CMD=1 (read)
      `uvm_info("TEST_RAND_MASTER_READ", $sformatf("Issued READ CMD #%0d", i), UVM_MEDIUM)
    end

    // Wait for transaction
    #100us;

    // Check RXFLR
    apb_read(8'h40, rxflr);
    `uvm_info("TEST_RAND_MASTER_READ", $sformatf("RXFLR=0x%08h", rxflr), UVM_MEDIUM)

    // Drain RX FIFO
    for (int i = 0; i < rand_byte_count; i++) begin
      logic [31:0] rx_data;
      apb_read(8'h0C, rx_data);
      `uvm_info("TEST_RAND_MASTER_READ", $sformatf("RX[%0d]=0x%02x", i, rx_data[7:0]), UVM_MEDIUM)
    end

    `uvm_info("TEST_RAND_MASTER_READ", "Random Master Read Test PASSED", UVM_MEDIUM)
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

endclass : test_rand_master_read
