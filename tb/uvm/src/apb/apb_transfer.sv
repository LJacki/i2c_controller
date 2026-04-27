// APB Transaction
import uvm_pkg::*;
class apb_transfer extends uvm_sequence_item;

  typedef enum { APB_READ, APB_WRITE } apb_kind_e;
  rand apb_kind_e kind;
  rand bit [7:0] addr;
  rand bit [31:0] data;
  rand int delay; // idle cycles between transfers

  `uvm_object_utils_begin(apb_transfer)
    `uvm_field_enum(apb_kind_e, kind, UVM_DEFAULT)
    `uvm_field_int(addr, UVM_DEFAULT)
    `uvm_field_int(data, UVM_DEFAULT)
    `uvm_field_int(delay, UVM_DEFAULT)
  `uvm_object_utils_end

  function new(string name = "apb_transfer");
    super.new(name);
  endfunction

  function string convert2string();
    if (kind == APB_WRITE)
      return $sformatf("APB_WRITE addr=0x%02h data=0x%08h", addr, data);
    else
      return $sformatf("APB_READ  addr=0x%02h data=0x%08h", addr, data);
  endfunction

endclass : apb_transfer