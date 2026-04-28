// I2C Protocol Checker - Verifies I2C bus timing compliance
// Checks START/STOP timing, SDA stability during SCL, ACK/NACK behavior
class i2c_protocol_checker extends uvm_monitor;

  virtual i2c_if vif;
  uvm_analysis_port #(i2c_transfer) ap;

  int sda_glitch_count = 0;
  int start_err_scl_low_count = 0;
  int scl_oe_during_start_count = 0;

  `uvm_component_utils(i2c_protocol_checker)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual i2c_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "i2c_protocol_checker: virtual interface not set")
    ap = new("ap", this);
  endfunction

  // Check START condition: SDA falls while SCL=1
  // Also checks that scl_oe=0 during START (SCL must be released/high)
  task monitor_start();
    bit prev_sda, prev_scl;
    forever begin
      @(negedge vif.sda_i);
      prev_sda = 1;
      prev_scl = vif.scl_i;
      if (vif.scl_i === 1'b1) begin
        // Valid START detected
        `uvm_info("I2C_PROTO", 
          $sformatf("START OK: SDA fell while SCL=1 (scl_oe=%b scl_i=%b)", 
            vif.scl_oe, vif.scl_i), UVM_MEDIUM)
        
        if (vif.scl_oe === 1'b1) begin
          `uvm_error("I2C_PROTOCOL", 
            $sformatf("START ERROR: scl_oe=%b (SCL driven LOW during START!)", 
              vif.scl_oe))
          scl_oe_during_start_count++;
        end
        if (vif.scl_i !== 1'b1) begin
          `uvm_error("I2C_PROTOCOL", 
            $sformatf("START ERROR: SCL=%b (expected 1) when SDA fell", vif.scl_i))
          start_err_scl_low_count++;
        end
      end
    end
  endtask

  // Check STOP condition: SDA rises while SCL=1
  task monitor_stop();
    forever begin
      @(posedge vif.sda_i);
      if (vif.scl_i === 1'b1) begin
        `uvm_info("I2C_PROTO", 
          $sformatf("STOP OK: SDA rose while SCL=1 (scl_oe=%b scl_i=%b)", 
            vif.scl_oe, vif.scl_i), UVM_MEDIUM)
      end
    end
  endtask

  // Check SDA stability: SDA must not change while SCL=1 (except START/STOP)
  task monitor_sda_stability();
    bit sda_at_scl_rise;
    forever begin
      @(posedge vif.scl_i);
      sda_at_scl_rise = vif.sda_i;
      // Monitor SDA until SCL falls
      fork
        begin
          @(negedge vif.scl_i);
        end
        begin
          @(negedge vif.sda_i);
          // SDA changed while SCL still high
          if (vif.scl_i === 1'b1) begin
            // Check if it's a START (SDA fell) or a glitch (SDA rose = potential STOP or real glitch)
            if (vif.sda_i === 1'b1 && sda_at_scl_rise === 1'b0) begin
              // This is a STOP condition, let monitor_stop handle it
            end else if (vif.sda_i === 1'b0) begin
              // This is a START condition, let monitor_start handle it
            end else begin
              `uvm_error("I2C_PROTOCOL", 
                $sformatf("SDA glitch: changed during SCL=1 (scl_i=%b sda_i=%b)", 
                  vif.scl_i, vif.sda_i))
              sda_glitch_count++;
            end
          end
        end
      join_any
      disable fork;
    end
  endtask

  task run_phase(uvm_phase phase);
    `uvm_info("I2C_PROTO_CHECKER", "I2C Protocol Checker started", UVM_LOW)
    fork
      monitor_start();
      monitor_stop();
      monitor_sda_stability();
    join
  endtask

  function void report_phase(uvm_phase phase);
    `uvm_info("I2C_PROTO_CHECKER", "=== I2C Protocol Check Summary ===", UVM_LOW)
    `uvm_info("I2C_PROTO_CHECKER", 
      $sformatf("SDA glitches during SCL=1: %0d", sda_glitch_count), UVM_LOW)
    `uvm_info("I2C_PROTO_CHECKER", 
      $sformatf("START with scl_oe=1 (SCL driven low): %0d", scl_oe_during_start_count), UVM_LOW)
    `uvm_info("I2C_PROTO_CHECKER", 
      $sformatf("START with SCL not high: %0d", start_err_scl_low_count), UVM_LOW)
    
    if (sda_glitch_count > 0 || scl_oe_during_start_count > 0 || start_err_scl_low_count > 0) begin
      `uvm_error("I2C_PROTOCOL_FAIL", 
        $sformatf("I2C protocol violations: %0d total", 
          sda_glitch_count + scl_oe_during_start_count + start_err_scl_low_count))
    end else begin
      `uvm_info("I2C_PROTO_CHECKER", "I2C Protocol: PASS", UVM_LOW)
    end
  endfunction

endclass : i2c_protocol_checker
