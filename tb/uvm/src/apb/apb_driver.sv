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

  // Keep run_phase alive but idle - test drives APB signals directly
  task run_phase(uvm_phase phase);
    forever begin
      @(posedge vif.pclk);
      // Idle: keep APB signals de-asserted
      vif.psel    <= 1'b0;
      vif.penable <= 1'b0;
      vif.pwrite  <= 1'b0;
      vif.paddr   <= 8'h0;
      vif.pwdata  <= 32'h0;
    end
  endtask

endclass : apb_driver
