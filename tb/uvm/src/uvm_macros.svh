// UVM macros - simplified embedded version for compilation
// Full version from VCS installation path: $VCS_HOME/etc/uvm/uvm_macros.svh

`ifndef UVM_MACROS_SVH
`define UVM_MACROS_SVH

// Object creation
`define uvm_object_utils(T)
`define uvm_object_utils_begin(T)
`define uvm_object_utils_end(T)
`define uvm_component_utils(T)
`define uvm_component_utils_begin(T)
`define uvm_component_utils_end(T)

// Field registration
`define uvm_field_int(ARG, FLAG)
`define uvm_field_enum(T, ARG, FLAG)
`define uvm_field_object(ARG, FLAG)
`define uvm_field_string(ARG, FLAG)

// Messaging
`define uvm_info(ID, MSG, VERB)
`define uvm_warning(ID, MSG)
`define uvm_error(ID, MSG)
`define uvm_fatal(ID, MSG)

// Sequence macros
`define uvm_sequence_utils(T)
`define uvm_declare_p_sequencer(T)

// Component creation macro
`define uvm_component_new(T, NAME, PARENT)
  begin
    super.new(NAME, PARENT);
  end

`endif