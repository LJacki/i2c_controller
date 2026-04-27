// I2C Transaction
import uvm_pkg::*;
class i2c_transfer extends uvm_sequence_item;

  typedef enum { I2C_WRITE, I2C_READ } i2c_kind_e;
  typedef enum { START, STOP, RESTART, ADDR, DATA, ACK, NACK } bit_type_e;

  rand i2c_kind_e kind;
  rand logic [6:0] addr;       // 7-logic target address
  rand logic [7:0] data[];     // dynamic array of data bytes
  rand logic        last_cmd;   // last command: 0=write, 1=read

  `uvm_object_utils_begin(i2c_transfer)
    `uvm_field_enum(i2c_kind_e, kind, UVM_DEFAULT)
    `uvm_field_int(addr, UVM_DEFAULT)
    `uvm_field_int(last_cmd, UVM_DEFAULT)
  `uvm_object_utils_end

  function new(string name = "i2c_transfer");
    super.new(name);
  endfunction

  function string convert2string();
    string s;
    s = $sformatf("I2C_%s addr=0x%02x last_cmd=%s", kind.name(), addr, last_cmd ? "READ" : "WRITE");
    if (data.size() > 0) begin
      s = {s, " data=["};
      foreach (data[i]) s = {s, $sformatf("0x%02x ", data[i])};
      s = {s, "]"};
    end
    return s;
  endfunction

endclass : i2c_transfer