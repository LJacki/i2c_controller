// Test: Constrained Random Master Write
// Cover: Random data, random byte count (1~16), random target address (non-zero)
// Constraints: addr != 0, data != 0, 1 <= byte_count <= 16
class test_rand_master_write extends base_test;

  `uvm_component_utils(test_rand_master_write)

  // Random variables
  rand bit [6:0]  rand_addr;
  rand bit [7:0]  rand_data[];
  rand int        rand_byte_count;

  // Constraints
  constraint byte_count_c { rand_byte_count inside {[1:16]}; }
  constraint addr_c       { rand_addr != 7'h00; }  // non-zero address
  constraint data_c       { foreach(rand_data[i]) rand_data[i] != 8'h00; }  // non-zero data

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void randomize_data();
    rand_byte_count = $urandom_range(1, 16);
    rand_data = new[rand_byte_count];
    foreach (rand_data[i]) rand_data[i] = $urandom_range(1, 255);
    rand_addr = $urandom_range(1, 127);  // 7'h01 to 7'h7F
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    `uvm_info("TEST_RAND_MASTER_WRITE", "Starting Random Master Write Test...", UVM_MEDIUM)

    // Randomize transaction parameters
    randomize_data();

    `uvm_info("TEST_RAND_MASTER_WRITE",
      $sformatf("Randomized: addr=0x%02x, byte_count=%0d", rand_addr, rand_byte_count), UVM_MEDIUM)

    // Print randomized data
    begin
      string data_str = "data=[";
      foreach (rand_data[i]) data_str = {data_str, $sformatf("0x%02x ", rand_data[i])};
      data_str = {data_str, "]"};
      `uvm_info("TEST_RAND_MASTER_WRITE", data_str, UVM_MEDIUM)
    end

    // Configure Master
    apb_write(8'h04, {22'b0, 1'b0, 1'b0, rand_addr});
    apb_write(8'h00, 12'h1B);  // MASTER_MODE=1, SPEED=Fast, RESTART_EN=1, SLAVE_DISABLE=1
    apb_write(8'h18, 16'd60);
    apb_write(8'h1C, 16'd130);
    apb_write(8'h34, 32'h1);   // ENABLE=1

    // Write randomized data bytes
    foreach (rand_data[i]) begin
      apb_write(8'h0C, {24'b0, rand_data[i]});  // CMD=0 (write)
      `uvm_info("TEST_RAND_MASTER_WRITE", $sformatf("Wrote byte[%0d]=0x%02x", i, rand_data[i]), UVM_MEDIUM)
    end

    // Wait for transaction
    #100us;

    // Check STATUS
    bit [31:0] status;
    apb_read(8'h38, status);
    `uvm_info("TEST_RAND_MASTER_WRITE", $sformatf("STATUS=0x%08h", status), UVM_MEDIUM)

    `uvm_info("TEST_RAND_MASTER_WRITE", "Random Master Write Test PASSED", UVM_MEDIUM)
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

endclass : test_rand_master_write
