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

  // Slave driver signals (for clock stretching and slave-driven SDA)
  // These allow the slave to pull SCL/SDA low independently
  logic slv_scl_oe;  // slave SCL output enable (1=driving low)
  logic slv_sda_oe;  // slave SDA output enable (1=driving low)
  logic slv_sda_o = 1'b1;  // slave SDA output value (default=1 so inactive driver doesn't pull low)

  // Tri-state bus with pull-up (mimics I2C open-drain)
  // Wire-AND model: when any device drives low, bus is low
  // scl_oe=1 -> drives 0 (pull low), scl_oe=0 -> released (pull-up = 1)
  assign scl_i = (scl_oe || slv_scl_oe) ? 1'b0 : 1'b1;
  // sda_i resolves based on which device(s) are driving
  assign sda_i = (sda_oe || slv_sda_oe) ? (sda_o && slv_sda_o) : 1'b1;

endinterface : i2c_if
