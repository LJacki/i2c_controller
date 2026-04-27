import uvm_pkg::*;

// I2C Master BFM (Bus Functional Model)
// Drives I2C bus as Master: START, address, data, ACK/NACK, STOP
class i2c_master_agent extends uvm_driver #(i2c_transfer);

  virtual i2c_if vif;
  uvm_analysis_port #(i2c_transfer) ap;
  uvm_sequencer #(i2c_transfer) sequencer;

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
    ap = new("ap", this);
    sequencer = uvm_sequencer #(i2c_transfer)::type_id::create("sequencer", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    seq_item_port.connect(sequencer.seq_item_export);
  endfunction

  // ============================================================
  // Public API: called by tests directly to drive I2C transactions
  // ============================================================

  // Drive a complete I2C write transaction (START -> ADDR+W -> DATA bytes -> STOP)
  task drive_i2c_write(input logic [6:0] addr, input logic [7:0] data);
    send_start();
    send_addr(addr, 1'b0);
    send_byte(data);
    send_stop();
  endtask

  // Drive I2C write with multiple data bytes
  task drive_i2c_write_multi(input logic [6:0] addr, input logic [7:0] data[$]);
    send_start();
    send_addr(addr, 1'b0);
    foreach (data[i]) send_byte(data[i]);
    send_stop();
  endtask

  // Drive a complete I2C read transaction (START -> ADDR+R -> DATA(NACK) -> STOP)
  // Inlined receive logic to avoid function-with-delay issue
  task drive_i2c_read(input logic [6:0] addr, output logic [7:0] data);
    logic [7:0] rcvd;
    send_start();
    send_addr(addr, 1'b1);
    // Receive 1 byte with NACK
    rcvd = 8'h0;
    release_sda();
    for (int i = 7; i >= 0; i--) begin
      drive_scl_high();
      rcvd[i] = vif.sda_i;
      drive_scl_low();
    end
    // Drive NACK
    vif.sda_o  <= 1'b1;
    vif.sda_oe <= 1'b1;
    drive_scl_high();
    drive_scl_low();
    vif.sda_oe <= 1'b0;
    `uvm_info("I2C_MASTER", $sformatf("RCVD 0x%02x ACK=0(NACK)", rcvd), UVM_MEDIUM)
    data = rcvd;
    send_stop();
  endtask

  // ============================================================
  // Internal bus driving tasks
  // ============================================================

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
  task drive_sda(logic val);
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
  task send_addr(logic [6:0] addr, logic rw);
    logic ack;
    logic [7:0] addr_byte = {addr, rw};
    for (int i = 7; i >= 0; i--) begin
      drive_sda(addr_byte[i]);
      drive_scl_high();
      drive_scl_low();
    end
    // Receive ACK
    release_sda();
    drive_scl_high();
    #100;  // Small delay for ACK sampling
    ack = vif.sda_i;  // 0=ACK, 1=NACK
    drive_scl_low();
    `uvm_info("I2C_MASTER", $sformatf("ADDR 0x%02x %s ACK=%b", addr, rw ? "READ" : "WRITE", ack), UVM_MEDIUM)
  endtask

  // Send 8-bit data byte
  task send_byte(logic [7:0] data);
    logic ack;
    for (int i = 7; i >= 0; i--) begin
      drive_sda(data[i]);
      drive_scl_high();
      drive_scl_low();
    end
    // Receive ACK
    release_sda();
    drive_scl_high();
    #100;
    ack = vif.sda_i;
    drive_scl_low();
    `uvm_info("I2C_MASTER", $sformatf("DATA 0x%02x ACK=%b", data, ack), UVM_MEDIUM)
  endtask

  // run_phase intentionally empty - tests drive I2C via drive_i2c_write/drive_i2c_read

endclass : i2c_master_agent
