// I2C Controller UVM Environment
class i2c_ctrl_env extends uvm_env;

  apb_driver            apb_drv;
  apb_monitor           apb_mon;
  i2c_master_agent      i2c_master;
  i2c_slave_agent       i2c_slave;
  i2c_bus_monitor       i2c_bus_mon;     // NEW: monitors I2C transactions
  i2c_protocol_checker  i2c_proto_chk;   // NEW: checks protocol compliance
  scoreboard            scb;

  uvm_analysis_port #(apb_transfer)  apb_ap;
  uvm_analysis_port #(i2c_transfer) i2c_ap;

  `uvm_component_utils(i2c_ctrl_env)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    apb_drv    = apb_driver::type_id::create("apb_drv", this);
    apb_mon    = apb_monitor::type_id::create("apb_mon", this);
    i2c_master = i2c_master_agent::type_id::create("i2c_master", this);
    i2c_slave  = i2c_slave_agent::type_id::create("i2c_slave", this);
    i2c_bus_mon = i2c_bus_monitor::type_id::create("i2c_bus_mon", this);
    i2c_proto_chk = i2c_protocol_checker::type_id::create("i2c_proto_chk", this);
    scb        = scoreboard::type_id::create("scb", this);

    apb_ap  = new("apb_ap", this);
    i2c_ap  = new("i2c_ap", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);

    // APB monitor -> scoreboard
    apb_mon.ap.connect(scb.apb_fifo.analysis_export);

    // I2C bus monitor -> scoreboard (this is key: scoreboard now gets real I2C transactions)
    i2c_bus_mon.ap.connect(scb.i2c_fifo.analysis_export);
  endfunction

endclass : i2c_ctrl_env
