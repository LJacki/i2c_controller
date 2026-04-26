// Base Test - foundation for all tests
class base_test extends uvm_test;

  i2c_ctrl_env       env;
  test_cfg           cfg;

  `uvm_component_utils(base_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    cfg = test_cfg::type_id::create("cfg");
    env = i2c_ctrl_env::type_id::create("env", this);

    // Set default config
    uvm_config_db #(test_cfg)::set(this, "*", "cfg", cfg);
  endfunction

  function void end_of_elaboration_phase(uvm_phase phase);
    super.end_of_elaboration_phase(phase);
    print();
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    `uvm_info("BASE_TEST", "Starting base test...", UVM_MEDIUM)
    #100us;
    `uvm_info("BASE_TEST", "Base test completed", UVM_MEDIUM)
    phase.drop_objection(this);
  endtask

endclass : base_test