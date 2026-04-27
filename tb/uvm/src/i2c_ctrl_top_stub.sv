// i2c_ctrl_top_stub.sv - DUT Stub for compilation verification
// SPEC v2.2 addresses: INTR_STAT=0x24, RAW_INTR_STAT=0x28, all subsequent +4
// Replace with actual RTL (i2c_ctrl_top.sv) when ready
module i2c_ctrl_top (
  input        pclk,
  input        presetn,
  input        psel,
  input        penable,
  input        pwrite,
  input  [7:0] paddr,
  input  [31:0] pwdata,
  output [31:0] prdata,
  output       pready,
  input        scl_i,
  output       scl_o,
  output       scl_oe,
  input        sda_i,
  output       sda_o,
  output       sda_oe,
  output       intr
);

  // Register file (v2.2 addresses)
  logic [31:0] CON, TAR, SAR, DATA_CMD;
  logic [15:0] SS_HCNT, SS_LCNT, FS_HCNT, FS_LCNT;
  logic [31:0] INTR_MASK;
  logic [31:0] INTR_STAT;    // 0x24 (post-mask)
  logic [31:0] RAW_INTR_STAT; // 0x28 (pre-mask)
  logic [4:0] RX_TL, TX_TL;  // 0x2C, 0x30
  logic [1:0] ENABLE;         // 0x34
  logic [31:0] STATUS;        // 0x38 (RO)
  logic [4:0] TXFLR, RXFLR;  // 0x3C, 0x40 (RO)
  logic [15:0] SDA_HOLD;     // 0x44
  logic [15:0] TX_ABRT_SOURCE; // 0x48 (RO, clr on read)
  logic [31:0] prdata_reg;
  logic [2:0]  ENABLE_STATUS;  // 0x4C (RO)

  wire [10:0] raw_intr;
  assign raw_intr = 11'b0;  // stub: all zero
  assign INTR_STAT = {21'b0, raw_intr & ~INTR_MASK[10:0]};
  assign STATUS = 32'b0;    // stub: all zero
  assign TXFLR = 5'b0;
  assign RXFLR = 5'b0;
  assign TX_ABRT_SOURCE = 16'b0;
  assign ENABLE_STATUS = {1'b0, 1'b0, 1'b0};  // IC_EN, SLV_ACT_DIS, MST_ACT_DIS

  // APB read logic (v2.2 addresses)
  always @(posedge pclk or negedge presetn) begin
    if (!presetn) begin
      prdata_reg <= 32'h0;
    end else if (psel && penable) begin
      case (paddr)
        8'h00: prdata_reg <= {20'b0, CON};
        8'h04: prdata_reg <= {22'b0, TAR};
        8'h08: prdata_reg <= {25'b0, SAR};
        8'h0C: prdata_reg <= {24'b0, DATA_CMD[7:0]};  // RX FIFO read
        8'h10: prdata_reg <= {16'b0, SS_HCNT};
        8'h14: prdata_reg <= {16'b0, SS_LCNT};
        8'h18: prdata_reg <= {16'b0, FS_HCNT};
        8'h1C: prdata_reg <= {16'b0, FS_LCNT};
        8'h20: prdata_reg <= INTR_MASK;
        8'h24: prdata_reg <= INTR_STAT;         // INTR_STAT (post-mask)
        8'h28: prdata_reg <= {21'b0, RAW_INTR_STAT}; // RAW_INTR_STAT (pre-mask)
        8'h2C: prdata_reg <= {27'b0, RX_TL};
        8'h30: prdata_reg <= {27'b0, TX_TL};
        8'h34: prdata_reg <= {30'b0, ENABLE};
        8'h38: prdata_reg <= STATUS;
        8'h3C: prdata_reg <= {27'b0, TXFLR};
        8'h40: prdata_reg <= {27'b0, RXFLR};
        8'h44: prdata_reg <= {16'b0, SDA_HOLD};
        8'h48: prdata_reg <= {16'b0, TX_ABRT_SOURCE};
        8'h4C: prdata_reg <= {29'b0, ENABLE_STATUS};
        default: prdata_reg <= 32'h0;  // undefined address = 0 (SPEC v2.2)
      endcase
    end
  end

  assign prdata = prdata_reg;
  assign pready = 1'b1;
  assign scl_o = 1'b0;
  assign scl_oe = 1'b0;
  assign sda_o = 1'b0;
  assign sda_oe = 1'b0;
  assign intr = 1'b0;

endmodule
