// I2C Interface definition
interface i2c_if ();

  // SCL signals
  logic scl_i;   // SCL input (from external or other master)
  logic scl_o;   // SCL output (master drive)
  logic scl_oe;  // SCL output enable

  // SDA signals
  logic sda_i;   // SDA input
  logic sda_o;   // SDA output
  logic sda_oe;  // SDA output enable

  // Internal tri-state resolve
  wire scl_wire = scl_oe ? scl_o : 1'bz;
  wire sda_wire = sda_oe ? sda_o : 1'bz;

  // Weak pull-up simulation (when output enable is 0)
  // Removed empty always block - was causing infinite loop hang

endinterface : i2c_if