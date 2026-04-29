import uvm_pkg::*;

// I2C Slave Agent - ACTIVE SLAVE RESPONDER (pure task-based)
// No function timing controls - all bus operations are tasks
// DUT master FSM drives real I2C transactions; this acts as I2C slave device
class i2c_slave_agent extends uvm_driver #(i2c_transfer);

  virtual i2c_if vif;
  uvm_analysis_port #(i2c_transfer) ap;
  logic [6:0] slave_addr = 7'h3C;

  `uvm_component_utils(i2c_slave_agent)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual i2c_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "i2c_slave_agent: virtual interface not set")
    ap = new("ap", this);
    void'(uvm_config_db #(logic [6:0])::get(this, "", "slave_addr", slave_addr));
  endfunction

  task run_phase(uvm_phase phase);
    slave_loop();
  endtask

  // ============================================================
  // Main loop
  // ============================================================
  task slave_loop();
    forever begin
      wait_start();
      handle_transaction();
      wait_stop();
    end
  endtask

  task wait_start();
    forever begin
      @(negedge vif.sda_i);
      if (vif.scl_i == 1'b1) begin
        `uvm_info("I2C_SLAVE", "START detected", UVM_MEDIUM)
        return;
      end
    end
  endtask

  task wait_stop();
    fork
      begin : wait_stop_fork
        forever begin
          @(posedge vif.sda_i);
          if (vif.scl_i == 1'b1) begin
            `uvm_info("I2C_SLAVE", "STOP detected", UVM_MEDIUM)
            disable wait_stop_fork;
          end
        end
      end
      begin
        #10ms;
        disable wait_stop_fork;
      end
    join_any
    disable fork;
  endtask

  // ============================================================
  // Transaction handler
  // ============================================================
  task handle_transaction();
    logic [7:0] addr_byte;
    logic read_bit;
    logic matched;
    logic [7:0] rx_byte;
    logic nack;
    logic [7:0] tx_byte;

    // Receive address + drive ACK immediately after last bit's falling edge
    recv_byte_noack(addr_byte, 1'b1);
    read_bit = addr_byte[0];
    matched = (addr_byte[7:1] == slave_addr);
    `uvm_info("I2C_SLAVE", $sformatf("ADDR=0x%02x R/W=%b matched=%b", addr_byte[7:1], read_bit, matched), UVM_MEDIUM)

    if (!matched) begin
      return;
    end

    // Data phase
    if (read_bit) begin
      // Master reads: slave drives bytes
      for (int j=0; j<16; j++) begin
        tx_byte = 8'h5A + j;
        drive_byte(tx_byte);
        sample_nack(nack);
        `uvm_info("I2C_SLAVE", $sformatf("TX[%0d]=0x%02x %s", j, tx_byte, nack ? "NACK" : "ACK"), UVM_MEDIUM)
        if (nack) break;
      end
    end else begin
      // Master writes: slave receives bytes
      forever begin
        // receive data byte (no ACK drive after data byte - master drives ACK/NACK)
        recv_byte_noack(rx_byte, 1'b0);
        sample_nack(nack);
        `uvm_info("I2C_SLAVE", $sformatf("RX=0x%02x nack=%b", rx_byte, nack), UVM_MEDIUM)
        if (nack) break;
        // Master sent ACK, continue receiving
      end
    end
  endtask

  // ============================================================
  // Bus primitives (all tasks - no function timing)
  // ============================================================

  // Receive 8 bits from master.
  // After the last bit's falling edge, immediately drive ACK if drive_ack_after=1.
  // FIX: ACK must be driven at the falling edge of the last bit (start of ACK bit),
  // NOT at the falling edge of the next byte's bit 0. By driving immediately when
  // SCL is already low, the master sees ACK at its sample point.
  task recv_byte_noack(output logic [7:0] data, input bit drive_ack_after = 0);
    data = 0;
    for (int i=7; i>=0; i--) begin
      @(posedge vif.scl_i);
      #80ns;
      data[i] = vif.sda_i;
      // Wait for this bit's falling edge (marks end of this bit's transfer)
      @(negedge vif.scl_i);
    end
    // At this point SCL is low (ACK bit period). Drive ACK immediately
    // so master sees it at the ACK bit's rising edge sample point.
    if (drive_ack_after) begin
      fork
        begin
          // SCL is already low - drive ACK immediately (no wait)
          vif.slv_sda_o <= 1'b0;
          vif.slv_sda_oe <= 1'b1;
          @(posedge vif.scl_i);  // Wait for rising edge (end of ACK bit)
          #80ns;
          vif.slv_sda_oe <= 1'b0;
          vif.slv_sda_o <= 1'b0;
        end
      join_none
    end
  endtask

  // Sample ACK/NACK bit from master
  task sample_nack(output logic nack);
    @(posedge vif.scl_i);
    #80ns;
    nack = vif.sda_i;
  endtask

  // Drive ACK: pull SDA low for ACK bit
  task drive_ack();
    @(negedge vif.scl_i);
    vif.slv_sda_o <= 1'b0;
    vif.slv_sda_oe <= 1'b1;
    @(posedge vif.scl_i);
    #80ns;
    vif.slv_sda_oe <= 1'b0;
    vif.slv_sda_o <= 1'b0;
  endtask

  // Drive one byte onto SDA then release
  task drive_byte(logic [7:0] data);
    // Drive 8 bits
    for (int i=7; i>=0; i--) begin
      @(negedge vif.scl_i);
      vif.slv_sda_o <= data[i];
      vif.slv_sda_oe <= 1'b1;
    end
    // Release SDA for ACK bit (let master drive ACK)
    @(negedge vif.scl_i);
    vif.slv_sda_oe <= 1'b0;
    vif.slv_sda_o <= 1'b0;
  endtask

endclass : i2c_slave_agent
