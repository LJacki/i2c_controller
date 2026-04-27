import uvm_pkg::*;

// I2C Slave BFM (Bus Functional Model)
// Responds to I2C transactions as a slave device
class i2c_slave_agent extends uvm_driver #(i2c_transfer);

  virtual i2c_if vif;
  uvm_analysis_port #(i2c_transfer) ap;
  uvm_sequencer #(i2c_transfer) sequencer;

  // Timing parameters
  real tperiod = 10us;
  real t_high  = 4.7us;
  real t_low   = 4.7us;

  // Configurable slave address (7-bit)
  logic [6:0] slave_addr = 7'h3C;  // default, can be overridden

  // TX data buffer for slave transmit
  logic [7:0] tx_data_queue[$];

  // Flags
  logic addr_match = 0;

  `uvm_component_utils(i2c_slave_agent)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual i2c_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "i2c_slave_agent: virtual interface not set")
    ap = new("ap", this);
    sequencer = uvm_sequencer #(i2c_transfer)::type_id::create("sequencer", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    seq_item_port.connect(sequencer.seq_item_export);
  endfunction

  // Drive ACK on SDA
  task drive_ack();
    vif.sda_o  <= 1'b0;
    vif.sda_oe <= 1'b1;
    drive_scl_pulse();
    vif.sda_oe <= 1'b0;  // Release SDA
  endtask

  // Drive NACK on SDA
  task drive_nack();
    vif.sda_oe <= 1'b0;   // Don't drive SDA (let pull-up drive high)
    drive_scl_pulse();
  endtask

  // Single SCL pulse (low->high->low)
  task drive_scl_pulse();
    vif.scl_oe <= 1'b0;
    #t_low;
    #t_high;
  endtask

  // Monitor SCL and SDA for start condition
  task wait_start();
    @(posedge vif.scl_i);
    if (vif.sda_i === 1'b0 && vif.scl_i === 1'b1) begin
      `uvm_info("I2C_SLAVE", "START detected", UVM_MEDIUM)
      // Wait for SCL to go low
      @(negedge vif.scl_i);
    end
  endtask

  // Receive address byte
  task receive_addr(output logic [6:0] addr, output logic rw);
    logic [7:0] rcvd_byte;
    for (int i = 7; i >= 0; i--) begin
      @(negedge vif.scl_i);
      rcvd_byte[i] = vif.sda_i;
    end
    addr = rcvd_byte[7:1];
    rw   = rcvd_byte[0];
    `uvm_info("I2C_SLAVE", $sformatf("RCVD ADDR 0x%02x R/W=%b", addr, rw), UVM_MEDIUM)
  endtask

  // Receive data byte
  task receive_data(output logic [7:0] data);
    for (int i = 7; i >= 0; i--) begin
      @(negedge vif.scl_i);
      data[i] = vif.sda_i;
    end
    `uvm_info("I2C_SLAVE", $sformatf("RCVD DATA 0x%02x", data), UVM_MEDIUM)
  endtask

  // Monitor SCL and SDA for stop condition
  task wait_stop();
    fork
      begin
        @(posedge vif.scl_i);
        if (vif.sda_i === 1'b1) begin
          `uvm_info("I2C_SLAVE", "STOP detected", UVM_MEDIUM)
        end
      end
    join_any
  endtask

  // Main slave run task
  task run_phase(uvm_phase phase);
    logic ack;
    reg [6:0]  rcvd_addr;
    logic         rw_bit;
    reg [7:0]  data;
    reg [7:0]   tx_byte;

    forever begin
      // Wait for START condition
      wait_start();

      // Receive address
      receive_addr(rcvd_addr, rw_bit);

      // Check address match
      if (rcvd_addr == slave_addr) begin
        addr_match = 1'b1;
        drive_ack();

        if (rw_bit == 1'b0) begin
          // === SLAVE RECEIVE MODE ===
          forever begin
            receive_data(data);
            // Send ACK
            drive_ack();
            // Check for STOP
            if (vif.scl_i === 1'b0 && vif.sda_i === 1'b1)
              break;
          end
        end else begin
          // === SLAVE TRANSMIT MODE ===
          if (tx_data_queue.size() > 0) begin
            tx_byte = tx_data_queue.pop_front();
            // Drive data onto SDA
            for (int i = 7; i >= 0; i--) begin
              vif.sda_o  <= tx_byte[i];
              vif.sda_oe <= 1'b1;
              @(negedge vif.scl_i);
            end
            vif.sda_oe <= 1'b0;
            // Monitor ACK/NACK from master
            @(posedge vif.scl_i);
            ack = vif.sda_i;
            `uvm_info("I2C_SLAVE", $sformatf("TX 0x%02x ACK=%b", tx_byte, ack), UVM_MEDIUM)
            @(negedge vif.scl_i);
          end else begin
            `uvm_info("I2C_SLAVE", "TX_FIFO empty - drive NACK", UVM_MEDIUM)
            drive_nack();
          end
        end
      end else begin
        `uvm_info("I2C_SLAVE", $sformatf("ADDR 0x%02x no match, remain silent", rcvd_addr), UVM_MEDIUM)
        addr_match = 1'b0;
      end

      wait_stop();
    end
  endtask

endclass : i2c_slave_agent