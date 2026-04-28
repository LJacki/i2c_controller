// I2C Interface definition
// Used by master/slave agents to monitor and drive I2C bus
interface i2c_if ();

  // SCL signals
  logic scl_i;   // SCL input (resolved bus value - what master sees on bus)
  logic scl_o;   // SCL output from master DUT
  logic scl_oe;  // SCL output enable (1=driving low, 0=tri-state)

  // SDA signals
  logic sda_i;   // SDA input (resolved bus value)
  logic sda_o;   // SDA output from master/slave
  logic sda_oe;  // SDA output enable

  // Tri-state bus with pull-up (mimics I2C open-drain)
  // scl_oe=1 -> drives 0 (pull low), scl_oe=0 -> released (pull-up = 1)
  assign scl_i = scl_oe ? 1'b0 : 1'b1;
  assign sda_i = sda_oe ? 1'b0 : 1'b1;

endinterface : i2c_if
