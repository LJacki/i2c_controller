// I2C Interface definition
// Used by master/slave agents to monitor and drive I2C bus
interface i2c_if ();

  // SCL signals
  logic scl_i;   // SCL input (from external or other master)
  logic scl_o;   // SCL output (master drive)
  logic scl_oe;  // SCL output enable (1=driving low, 0=tri-state/pullup)

  // SDA signals
  logic sda_i;   // SDA input
  logic sda_o;   // SDA output (master/slave drive)
  logic sda_oe;  // SDA output enable

  // Internal tri-state resolve (actual bus level)
  wire scl_wire;
  wire sda_wire;

  assign scl_wire = scl_oe ? scl_o : 1'bz;
  assign sda_wire = sda_oe ? sda_o : 1'bz;

endinterface : i2c_if
