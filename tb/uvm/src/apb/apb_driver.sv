// APB Driver (BFM style)
// Drives APB signals based on apb_transfer items
class apb_driver extends uvm_driver #(apb_transfer);

  virtual apb_if vif;

  `uvm_component_utils(apb_driver)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual apb_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "apb_driver: virtual interface not set")
  endfunction

  task run_phase(uvm_phase phase);
    forever begin
      apb_transfer tr;
      @(posedge vif.pclk);
      vif.psel    <= 1'b0;
      vif.penable <= 1'b0;
      vif.pwrite  <= 1'b0;
      vif.paddr   <= 8'h0;
      vif.pwdata  <= 32'h0;

      seq_item_port.get_next_item(tr);

      // Execute APB transfer with pready=1 (no wait states)
      @(posedge vif.pclk);
      vif.psel    <= 1'b1;
      vif.penable <= 1'b0;
      vif.pwrite  <= (tr.kind == apb_transfer::APB_WRITE);
      vif.paddr   <= tr.addr;
      vif.pwdata  <= tr.data;

      @(posedge vif.pclk);
      vif.penable <= 1'b1;
      @(posedge vif.pclk);

      // Wait for pready (fixed at 1)
      while (!vif.pready) @(posedge vif.pclk);

      // Capture read data
      if (tr.kind == apb_transfer::APB_READ) begin
        tr.data = vif.prdata;
        `uvm_info("APB_DRV", $sformatf("READ  addr=0x%02h data=0x%08h", tr.addr, vif.prdata), UVM_MEDIUM)
      end else begin
        `uvm_info("APB_DRV", $sformatf("WRITE addr=0x%02h data=0x%08h", tr.addr, tr.data), UVM_MEDIUM)
      end

      @(posedge vif.pclk);
      vif.psel    <= 1'b0;
      vif.penable <= 1'b0;

      seq_item_port.item_done();

      // Optional delay between transfers
      if (tr.delay > 0) begin
        repeat(tr.delay) @(posedge vif.pclk);
      end
    end
  endtask

endclass : apb_driver