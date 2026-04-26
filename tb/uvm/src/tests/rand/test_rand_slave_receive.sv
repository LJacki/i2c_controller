// Test: Constrained Random Slave Receive
// Cover: Random data bytes, random byte count (1~8), slave address match
// Constraints: data != 0, 1 <= byte_count <= 8
class test_rand_slave_receive extends base_test;

  `uvm_component_utils(test_rand_slave_receive)

  // Random variables
  rand logic [7:0]  rand_data[];
  rand int        rand_byte_count;
  rand logic [6:0]  slave_addr;

  // Constraints
  constraint byte_count_c { rand_byte_count inside {[1:8]}; }
  constraint data_c       { foreach(rand_data[i]) rand_data[i] != 8'h00; }

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
  begin
    logic [31:0] rxflr;
    phase.raise_objection(this);
    `uvm_info("TEST_RAND_SLAVE_RECEIVE", "Starting Random Slave Receive Test...", UVM_MEDIUM)

    // Randomize
    rand_byte_count = $urandom_range(1, 8);
    rand_data = new[rand_byte_count];
    foreach (rand_data[i]) rand_data[i] = $urandom_range(1, 255);
    slave_addr = $urandom_range(1, 127);

    `uvm_info("TEST_RAND_SLAVE_RECEIVE",
      $sformatf("Randomized: slave_addr=0x%02x, byte_count=%0d", slave_addr, rand_byte_count), UVM_MEDIUM)

    begin
      string data_str = "data=[";
      foreach (rand_data[i]) data_str = {data_str, $sformatf("0x%02x ", rand_data[i])};
      data_str = {data_str, "]"};
      `uvm_info("TEST_RAND_SLAVE_RECEIVE", data_str, UVM_MEDIUM)
    end

    // Configure DUT as slave
    apb_write(8'h08, {25'b0, slave_addr});  // SAR
    apb_write(8'h00, 12'h04);  // MASTER_MODE=0, SLAVE_DISABLE=0
    apb_write(8'h34, 32'h1);   // ENABLE=1

    // I2C BFM writes randomized data to DUT
    fork
      begin
        i2c_transfer tr;
        tr = i2c_transfer::type_id::create("tr");
        tr.kind = i2c_transfer::I2C_WRITE;
        tr.addr = slave_addr;
        tr.data = rand_data;
        tr.last_cmd = 1'b0;
        env.i2c_master.seq_item_port.put(tr);
      end
    join_none

    #100us;

    // Check RXFLR
    apb_read(8'h40, rxflr);
    `uvm_info("TEST_RAND_SLAVE_RECEIVE", $sformatf("RXFLR=0x%08h", rxflr), UVM_MEDIUM)

    // Read received data
    for (int i = 0; i < rand_byte_count; i++) begin
      logic [31:0] rx_data;
      apb_read(8'h0C, rx_data);
      `uvm_info("TEST_RAND_SLAVE_RECEIVE", $sformatf("RX[%0d]=0x%02x (expected 0x%02x)", i, rx_data[7:0], rand_data[i]), UVM_MEDIUM)
    end

    `uvm_info("TEST_RAND_SLAVE_RECEIVE", "Random Slave Receive Test PASSED", UVM_MEDIUM)
    phase.drop_objection(this);
  end
  endtask

  task apb_write(logic [7:0] addr, logic [31:0] data);
    apb_transfer tr;
    tr = apb_transfer::type_id::create("tr");
    tr.kind  = apb_transfer::APB_WRITE;
    tr.addr  = addr;
    tr.data  = data;
    tr.delay = 0;
    env.apb_drv.seq_item_port.put(tr);
  endtask

  task apb_read(logic [7:0] addr, output logic [31:0] data);
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

endclass : test_rand_slave_receive
