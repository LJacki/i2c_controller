# I2C Controller Verification - VCS Source Files

# === INTERFACES (must be at top level, before package) ===
+incdir+tb/uvm/src
tb/uvm/src/apb/apb_if.sv
tb/uvm/src/i2c/i2c_if.sv
tb/uvm/src/uvm_macros.svh

# === PACKAGE (includes all sub-components via `include) ===
tb/uvm/src/i2c_ctrl_pkg.sv

# Testbench top (uses i2c_ctrl_pkg)
tb/uvm/src/tests/tb_top.sv

# RTL Stub
