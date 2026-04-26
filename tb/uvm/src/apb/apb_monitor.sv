// APB Monitor
// Samples APB bus and reports transactions to analysis port
class apb_monitor extends uvm_monitor;

  virtual apb_if vif;
  uvm_analysis_port #(apb_transfer) ap;

  `uvm_component_utils(apb_monitor)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
    if (!uvm_config_db #(virtual apb_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "apb_monitor: virtual interface not set")
  endfunction

  task run_phase(uvm_phase phase);
    apb_transfer tr;
    bit [31:0] captured_data;

    forever begin
      @(posedge vif.pclk);

      // Wait for start of APB transfer
      if (vif.psel && !vif.penable) begin
        tr = apb_transfer::type_id::create("tr");
        tr.kind  = (vif.pwrite) ? apb_transfer::APB_WRITE : apb_transfer::APB_READ;
        tr.addr  = vif.paddr;

        @(posedge vif.pclk);
        if (vif.penable) begin
          tr.data = vif.pwrite ? vif.pwdata : vif.prdata;
          `uvm_info("APB_MON", tr.convert2string(), UVM_MEDIUM)
          ap.write(tr);
        end
      end
    end
  endtask

endclass : apb_monitor