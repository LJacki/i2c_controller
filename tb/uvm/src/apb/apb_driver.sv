// APB Driver (BFM style)
// Drives APB signals based on apb_transfer items
// Note: run_phase kept idle; test drives signals directly via vif
class apb_driver extends uvm_driver #(apb_transfer);

  virtual apb_if vif;
  uvm_sequencer #(apb_transfer) sequencer;

  `uvm_component_utils(apb_driver)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual apb_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "apb_driver: virtual interface not set")
    sequencer = uvm_sequencer #(apb_transfer)::type_id::create("sequencer", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    seq_item_port.connect(sequencer.seq_item_export);
  endfunction

  // NOTE: Do NOT drive APB signals here.
  // Test directly drives vif via env.apb_drv.vif for maximum control.
  // Driving signals here creates NBA conflicts with test's blocking assignments.
  task run_phase(uvm_phase phase);
    // Stay alive but do nothing - let test drive all APB signaling
    phase.raise_objection(this);
    #(1000s);  // Wait forever (until test ends)
    phase.drop_objection(this);
  endtask

endclass : apb_driver
