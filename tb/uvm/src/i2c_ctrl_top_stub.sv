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
  reg [31:0] CON, TAR, SAR, DATA_CMD;
  reg [15:0] SS_HCNT, SS_LCNT, FS_HCNT, FS_LCNT;
  reg [31:0] INTR_MASK;
  reg [31:0] INTR_STAT;    // 0x24 (post-mask)
  reg [31:0] RAW_INTR_STAT; // 0x28 (pre-mask)
  reg [4:0] RX_TL, TX_TL;  // 0x2C, 0x30
  reg [1:0] ENABLE;         // 0x34
  reg [31:0] STATUS;        // 0x38 (RO)
  reg [4:0] TXFLR, RXFLR;  // 0x3C, 0x40 (RO)
  reg [15:0] SDA_HOLD;     // 0x44
  reg [15:0] TX_ABRT_SOURCE; // 0x48 (RO, clr on read)
  reg [2:0]  ENABLE_STATUS;  // 0x4C (RO)

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
      prdata <= 32'h0;
    end else if (psel && penable) begin
      case (paddr)
        8'h00: prdata <= {20'b0, CON};
        8'h04: prdata <= {22'b0, TAR};
        8'h08: prdata <= {25'b0, SAR};
        8'h0C: prdata <= {24'b0, DATA_CMD[7:0]};  // RX FIFO read
        8'h10: prdata <= {16'b0, SS_HCNT};
        8'h14: prdata <= {16'b0, SS_LCNT};
        8'h18: prdata <= {16'b0, FS_HCNT};
        8'h1C: prdata <= {16'b0, FS_LCNT};
        8'h20: prdata <= INTR_MASK;
        8'h24: prdata <= INTR_STAT;         // INTR_STAT (post-mask)
        8'h28: prdata <= {21'b0, RAW_INTR_STAT}; // RAW_INTR_STAT (pre-mask)
        8'h2C: prdata <= {27'b0, RX_TL};
        8'h30: prdata <= {27'b0, TX_TL};
        8'h34: prdata <= {30'b0, ENABLE};
        8'h38: prdata <= STATUS;
        8'h3C: prdata <= {27'b0, TXFLR};
        8'h40: prdata <= {27'b0, RXFLR};
        8'h44: prdata <= {16'b0, SDA_HOLD};
        8'h48: prdata <= {16'b0, TX_ABRT_SOURCE};
        8'h4C: prdata <= {29'b0, ENABLE_STATUS};
        default: prdata <= 32'h0;  // undefined address = 0 (SPEC v2.2)
      endcase
    end
  end

  // APB write logic (v2.2 addresses)
  always @(posedge pclk or negedge presetn) begin
    if (!presetn) begin
      CON <= 32'h0; TAR <= 32'h0; SAR <= 32'h0; DATA_CMD <= 32'h0;
      SS_HCNT <= 16'd400; SS_LCNT <= 16'd400;
      FS_HCNT <= 16'd60; FS_LCNT <= 16'd130;
      INTR_MASK <= 32'hFFF;
      RX_TL <= 5'h0; TX_TL <= 5'h0;
      ENABLE <= 2'h0; SDA_HOLD <= 16'h1;
    end else if (psel && penable && pwrite) begin
      case (paddr)
        8'h00: CON      <= pwdata[11:0];
        8'h04: TAR      <= pwdata[9:0];
        8'h08: SAR      <= pwdata[6:0];
        8'h0C: DATA_CMD <= pwdata;  // TX FIFO write
        8'h10: SS_HCNT  <= pwdata[15:0];
        8'h14: SS_LCNT  <= pwdata[15:0];
        8'h18: FS_HCNT  <= pwdata[15:0];
        8'h1C: FS_LCNT  <= pwdata[15:0];
        8'h20: INTR_MASK <= pwdata;
        // 0x24: INTR_STAT = RO, no write
        // 0x28: RAW_INTR_STAT = RO, no write
        8'h2C: RX_TL    <= pwdata[4:0];
        8'h30: TX_TL    <= pwdata[4:0];
        8'h34: ENABLE  <= pwdata[1:0];
        // 0x38 STATUS: RO, no write
        // 0x3C TXFLR: RO, no write
        // 0x40 RXFLR: RO, no write
        8'h44: SDA_HOLD <= pwdata[15:0];
        // 0x48 TX_ABORT_SOURCE: RO, no write
        // 0x4C ENABLE_STATUS: RO, no write
      endcase
    end
  end

  // pready fixed at 1 (no wait states)
  assign pready = 1'b1;

  // I2C output enables (stub: all passive)
  assign scl_o = 1'b0;
  assign scl_oe = 1'b0;
  assign sda_o = 1'b0;
  assign sda_oe = 1'b0;
  assign intr = 1'b0;

endmodule : i2c_ctrl_top
