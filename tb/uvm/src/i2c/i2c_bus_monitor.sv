// I2C Bus Monitor - Passive protocol monitor
// Detects and extracts I2C transactions from the physical bus
// Sends i2c_transfer objects to scoreboard for verification
class i2c_bus_monitor extends uvm_monitor;

  virtual i2c_if vif;
  uvm_analysis_port #(i2c_transfer) ap;
  bit sda_prev;

  `uvm_component_utils(i2c_bus_monitor)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual i2c_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "i2c_bus_monitor: virtual interface not set")
    ap = new("ap", this);
  endfunction

  // Sample 8 bits MSB-first at SCL rising edge
  task automatic sample_byte(output bit [7:0] byte_out);
    bit [7:0] bits;
    for (int i = 7; i >= 0; i--) begin
      @(posedge vif.scl_i);
      bits[i] = vif.sda_i;
      @(negedge vif.scl_i);
    end
    byte_out = bits;
  endtask

  // Sample ACK/NACK bit at SCL rising edge
  task automatic check_ack(output bit ack_out);
    @(posedge vif.scl_i);
    ack_out = vif.sda_i;
    @(negedge vif.scl_i);
    `uvm_info("I2C_MON", $sformatf("ACK/NACK: %s", ack_out ? "NACK" : "ACK"), UVM_MEDIUM)
  endtask

  // Wait for START: SDA falls while SCL=1
  task wait_start_condition();
    forever begin
      @(negedge vif.sda_i);
      if (vif.scl_i === 1'b1) begin
        `uvm_info("I2C_MON", "START detected: SDA fell while SCL=1", UVM_MEDIUM)
        return;
      end
    end
  endtask

  task run_phase(uvm_phase phase);
    bit [7:0] addr_byte;
    bit [7:0] data_byte;
    bit rwn_bit;
    bit ack_bit;
    i2c_transfer tr;
    
    sda_prev = 1'b1;
    
    // Background: track SDA transitions for STOP detection
    fork
      forever begin
        sda_prev = vif.sda_i;
        @(vif.sda_i);
      end
    join_none
    
    forever begin
      // ---- Wait for START ----
      wait_start_condition();
      
      `uvm_info("I2C_MON", "=== I2C Transaction Start ===", UVM_MEDIUM)
      
      tr = i2c_transfer::type_id::create("tr", this);
      tr.kind = i2c_transfer::I2C_WRITE;
      tr.data = '{};  // empty dynamic array

      // ---- Address byte (7 bits + R/W) ----
      sample_byte(addr_byte);
      rwn_bit = addr_byte[0];
      tr.addr = addr_byte[7:1];
      tr.kind = (rwn_bit == 1'b0) ? i2c_transfer::I2C_WRITE : i2c_transfer::I2C_READ;
      `uvm_info("I2C_MON", $sformatf("ADDR: 0x%02x R/W=%b (%s)", tr.addr, rwn_bit, tr.kind.name()), UVM_MEDIUM)
      
      // Address ACK cycle
      check_ack(ack_bit);

      // ---- Data bytes loop ----
      forever begin
        sample_byte(data_byte);
        tr.data = new[tr.data.size() + 1](tr.data);
        tr.data[tr.data.size()-1] = data_byte;
        `uvm_info("I2C_MON", $sformatf("DATA[%0d]: 0x%02x", tr.data.size()-1, data_byte), UVM_MEDIUM)
        
        // ACK/NACK after each byte
        check_ack(ack_bit);
        
        // NACK means end of reception (last byte for READ)
        if (ack_bit === 1'b1) begin
          `uvm_info("I2C_MON", "NACK -> end of transfer", UVM_MEDIUM)
          tr.last_cmd = 1'b1;
          break;
        end
        
        tr.last_cmd = 1'b0;
        
        // STOP: SDA rises while SCL=1
        if (vif.scl_i === 1'b1 && sda_prev === 1'b0 && vif.sda_i === 1'b1) begin
          `uvm_info("I2C_MON", "STOP detected after data", UVM_MEDIUM)
          break;
        end
      end
      
      // ---- Send transaction to scoreboard ----
      `uvm_info("I2C_MON", $sformatf("TX completed: %s", tr.convert2string()), UVM_MEDIUM)
      ap.write(tr);
    end
  endtask

endclass : i2c_bus_monitor
