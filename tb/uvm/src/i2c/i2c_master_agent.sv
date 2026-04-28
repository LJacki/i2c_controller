import uvm_pkg::*;

// I2C Master Agent - PASSIVE MONITOR (not active driver)
// When DUT master FSM drives I2C transactions, this agent monitors them
// Tests should NOT call drive_i2c_write/read - DUT FSM drives the bus
class i2c_master_agent extends uvm_driver #(i2c_transfer);

  virtual i2c_if vif;
  uvm_analysis_port #(i2c_transfer) ap;
  uvm_sequencer #(i2c_transfer) sequencer;

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

  // run_phase: PASSIVE - only monitors, never drives
  // DUT master FSM must drive the I2C transaction
  task run_phase(uvm_phase phase);
    forever #1us;  // idle - we only monitor, don't drive
  endtask

endclass : i2c_master_agent
