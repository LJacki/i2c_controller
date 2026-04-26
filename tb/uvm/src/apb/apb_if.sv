// APB Interface definition
interface apb_if (
  input pclk,
  input presetn
);
  logic       psel;
  logic       penable;
  logic       pwrite;
  logic [7:0] paddr;
  logic [31:0] pwdata;
  logic [31:0] prdata;
  logic       pready;

  // Clocking block for drivers/monitors
  clocking drv_cb @(posedge pclk);
    output psel;
    output penable;
    output pwrite;
    output paddr;
    output pwdata;
    input  prdata;
    input  pready;
  endclocking

  clocking mon_cb @(posedge pclk);
    input psel;
    input penable;
    input pwrite;
    input paddr;
    input pwdata;
    input prdata;
    input pready;
  endclocking

endinterface : apb_if