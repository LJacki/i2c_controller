// Minimal DUT Stub for compilation verification
// This is a placeholder - replace with actual RTL when available
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

  // Register file
  reg [31:0] CON, TAR, SAR, DATA_CMD;
  reg [15:0] SS_HCNT, SS_LCNT, FS_HCNT, FS_LCNT;
  reg [31:0] INTR_MASK, RAW_INTR;
  reg [4:0] RX_TL, TX_TL;
  reg [1:0] ENABLE;
  reg [15:0] SDA_HOLD;

  // APB read logic
  always @(posedge pclk or negedge presetn) begin
    if (!presetn) begin
      prdata <= 32'h0;
      CON <= 32'h0; TAR <= 32'h0; SAR <= 32'h0; DATA_CMD <= 32'h0;
      SS_HCNT <= 16'd400; SS_LCNT <= 16'd400;
      FS_HCNT <= 16'd60; FS_LCNT <= 16'd130;
      INTR_MASK <= 32'hFFF; RX_TL <= 5'h0; TX_TL <= 5'h0;
      ENABLE <= 2'h0; SDA_HOLD <= 16'h1;
    end else if (psel && penable) begin
      case (paddr)
        8'h00: prdata <= {20'b0, CON};
        8'h04: prdata <= {22'b0, TAR};
        8'h08: prdata <= {25'b0, SAR};
        8'h0C: prdata <= {23'b0, DATA_CMD};
        8'h10: prdata <= {16'b0, SS_HCNT};
        8'h14: prdata <= {16'b0, SS_LCNT};
        8'h18: prdata <= {16'b0, FS_HCNT};
        8'h1C: prdata <= {16'b0, FS_LCNT};
        8'h20: prdata <= INTR_MASK;
        8'h28: prdata <= {27'b0, RX_TL};
        8'h2C: prdata <= {27'b0, TX_TL};
        8'h30: prdata <= {30'b0, ENABLE};
        8'h40: prdata <= {16'b0, SDA_HOLD};
        default: prdata <= 32'h0;
      endcase
    end
  end

  // APB write logic
  always @(posedge pclk or negedge presetn) begin
    if (!presetn) begin
      CON <= 32'h0; TAR <= 32'h0; SAR <= 32'h0; DATA_CMD <= 32'h0;
      SS_HCNT <= 16'd400; SS_LCNT <= 16'd400;
      FS_HCNT <= 16'd60; FS_LCNT <= 16'd130;
      INTR_MASK <= 32'hFFF; RX_TL <= 5'h0; TX_TL <= 5'h0;
      ENABLE <= 2'h0; SDA_HOLD <= 16'h1;
    end else if (psel && penable && pwrite) begin
      case (paddr)
        8'h00: CON <= pwdata[11:0];
        8'h04: TAR <= pwdata[9:0];
        8'h08: SAR <= pwdata[6:0];
        8'h0C: DATA_CMD <= pwdata;  // Write to TX FIFO
        8'h10: SS_HCNT <= pwdata[15:0];
        8'h14: SS_LCNT <= pwdata[15:0];
        8'h18: FS_HCNT <= pwdata[15:0];
        8'h1C: FS_LCNT <= pwdata[15:0];
        8'h20: INTR_MASK <= pwdata;
        8'h28: RX_TL <= pwdata[4:0];
        8'h2C: TX_TL <= pwdata[4:0];
        8'h30: ENABLE[0] <= pwdata[0];  // ABORT would be pwdata[1]
        8'h40: SDA_HOLD <= pwdata[15:0];
      endcase
    end
  end

  // pready is always 1 (no wait states)
  assign pready = 1'b1;

  // I2C output enables (simple pass-through for stub)
  assign scl_o = 1'b0;
  assign scl_oe = 1'b0;
  assign sda_o = 1'b0;
  assign sda_oe = 1'b0;
  assign intr = 1'b0;

endmodule : i2c_ctrl_top