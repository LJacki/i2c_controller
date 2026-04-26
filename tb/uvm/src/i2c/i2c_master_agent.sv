// I2C Master BFM (Bus Functional Model)
// Drives I2C bus as Master: START, address, data, ACK/NACK, STOP
class i2c_master_agent extends uvm_driver #(i2c_transfer);

  virtual i2c_if vif;

  // Timing parameters (default: 100kHz standard mode)
  real tperiod = 10us;   // SCL period
  real t_high  = 4.7us;  // SCL high time
  real t_low   = 4.7us;  // SCL low time

  `uvm_component_utils(i2c_master_agent)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual i2c_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "i2c_master_agent: virtual interface not set")
  endfunction

  // Drive SCL high (allow slave to drive low for clock stretching)
  task drive_scl_high();
    vif.scl_oe <= 1'b0;  // Tri-state SCL
    #t_high;
  endtask

  // Drive SCL low (master drives low)
  task drive_scl_low();
    vif.scl_o  <= 1'b0;
    vif.scl_oe <= 1'b1;  // Drive SCL low
    #t_low;
  endtask

  // Drive SDA
  task drive_sda(bit val);
    vif.sda_o  <= val;
    vif.sda_oe <= 1'b1;   // Drive SDA
  endtask

  // Release SDA (tri-state)
  task release_sda();
    vif.sda_oe <= 1'b0;   // SDA tri-state
  endtask

  // START condition: SDA 1->0 while SCL=1
  task send_start();
    release_sda();
    drive_scl_high();
    drive_sda(1'b0);      // SDA fall while SCL=1
    drive_scl_low();
    `uvm_info("I2C_MASTER", "START sent", UVM_MEDIUM)
  endtask

  // STOP condition: SDA 0->1 while SCL=1
  task send_stop();
    drive_sda(1'b0);
    drive_scl_low();
    release_sda();
    drive_scl_high();
    drive_sda(1'b1);      // SDA rise while SCL=1
    `uvm_info("I2C_MASTER", "STOP sent", UVM_MEDIUM)
  endtask

  // Repeated START
  task send_restart();
    release_sda();
    drive_scl_high();
    drive_sda(1'b0);      // SDA fall while SCL=1
    drive_scl_low();
    `uvm_info("I2C_MASTER", "RESTART sent", UVM_MEDIUM)
  endtask

  // Send 7-bit address + R/W bit
  task send_addr(bit [6:0] addr, bit rw);
    bit [7:0] addr_byte = {addr, rw};
    for (int i = 7; i >= 0; i--) begin
      drive_sda(addr_byte[i]);
      drive_scl_high();
      drive_scl_low();
    end
    // Receive ACK
    release_sda();
    drive_scl_high();
    #100;  // Small delay for ACK sampling
    bit ack = vif.sda_i;  // 0=ACK, 1=NACK
    drive_scl_low();
    `uvm_info("I2C_MASTER", $sformatf("ADDR 0x%02x %s ACK=%b", addr, rw ? "READ" : "WRITE", ack), UVM_MEDIUM)
  endtask

  // Send 8-bit data byte
  task send_byte(bit [7:0] data);
    for (int i = 7; i >= 0; i--) begin
      drive_sda(data[i]);
      drive_scl_high();
      drive_scl_low();
    end
    // Receive ACK
    release_sda();
    drive_scl_high();
    #100;
    bit ack = vif.sda_i;
    drive_scl_low();
    `uvm_info("I2C_MASTER", $sformatf("DATA 0x%02x ACK=%b", data, ack), UVM_MEDIUM)
  endtask

  // Receive byte and drive ACK/NACK
  task receive_byte(output bit [7:0] data, bit ack);
    data = 8'h0;
    release_sda();
    for (int i = 7; i >= 0; i--) begin
      drive_scl_high();
      data[i] = vif.sda_i;
      drive_scl_low();
    end
    // Drive ACK/NACK
    drive_sda(ack ? 1'b1 : 1'b0);
    drive_scl_high();
    drive_scl_low();
    `uvm_info("I2C_MASTER", $sformatf("RCVD 0x%02x ACK=%b", data, ack), UVM_MEDIUM)
  endtask

  task run_phase(uvm_phase phase);
    forever begin
      i2c_transfer tr;
      seq_item_port.get_next_item(tr);

      `uvm_info("I2C_MASTER", {"Executing: ", tr.convert2string()}, UVM_MEDIUM)

      send_start();
      send_addr(tr.addr, (tr.kind == i2c_transfer::I2C_READ));

      // Send/recv data bytes
      foreach (tr.data[i]) begin
        if (tr.kind == i2c_transfer::I2C_WRITE) begin
          bit ack;
          send_byte(tr.data[i]);
          // ACK from slave (sampled, not driven by master)
        end else begin
          bit ack_nack = (i == tr.data.size() - 1) ? 1'b1 : 1'b0; // NACK last byte
          receive_byte(tr.data[i], ack_nack);
        end
      end

      // Send STOP if last_cmd=0 (write) or last_cmd=1 (read with NACK already sent)
      send_stop();

      seq_item_port.item_done();
    end
  endtask

endclass : i2c_master_agent