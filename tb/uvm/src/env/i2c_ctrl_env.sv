// I2C Controller UVM Environment
class i2c_ctrl_env extends uvm_env;

  apb_driver        apb_drv;
  apb_monitor       apb_mon;
  i2c_master_agent  i2c_master;
  i2c_slave_agent  i2c_slave;
  scoreboard        scb;

  uvm_analysis_port #(apb_transfer)  apb_ap;
  uvm_analysis_port #(i2c_transfer)  i2c_ap;

  `uvm_component_utils(i2c_ctrl_env)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    apb_drv   = apb_driver::type_id::create("apb_drv", this);
    apb_mon   = apb_monitor::type_id::create("apb_mon", this);
    i2c_master = i2c_master_agent::type_id::create("i2c_master", this);
    i2c_slave = i2c_slave_agent::type_id::create("i2c_slave", this);
    scb       = scoreboard::type_id::create("scb", this);

    apb_ap = new("apb_ap", this);
    i2c_ap = new("i2c_ap", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);

    // Connect APB monitor to scoreboard via analysis port
    apb_mon.ap.connect(scb.apb_fifo.analysis_export);
    i2c_master.ap.connect(scb.i2c_fifo.analysis_export);
  endfunction

endclass : i2c_ctrl_env