// apb_reg_file.sv - APB Register File for I2C Controller
// 20 registers at offsets 0x00~0x4C (SPEC v2.2)
// pready fixed at 1 (no wait states)
// INTR_STAT at 0x24 (post-mask), RAW_INTR_STAT at 0x28 (pre-mask)

module apb_reg_file (
    input  logic pclk,
    input  logic presetn,   // async reset, active low

    // APB interface
    input  logic [7:0]  paddr,
    input  logic        psel,
    input  logic        penable,
    input  logic        pwrite,
    input  logic [31:0] pwdata,
    output logic [31:0] prdata,
    output logic        pready,   // fixed 1

    // Register outputs (to other modules)
    output logic [10:0] ic_tar,
    output logic [6:0] ic_sar,
    output logic        master_mode,
    output logic [1:0]  speed,
    output logic        restart_en,
    output logic        slave_disable,
    output logic [15:0] ss_hcnt,
    output logic [15:0] ss_lcnt,
    output logic [15:0] fs_hcnt,
    output logic [15:0] fs_lcnt,
    output logic [10:0] intr_mask,
    output logic [4:0]  rx_tl,
    output logic [4:0]  tx_tl,
    output logic        enable,
    output logic        abort,
    output logic [15:0] sda_hold,

    // FIFO / bus status inputs
    input  logic [4:0]  txflr,
    input  logic [4:0]  rxflr,
    input  logic        activity,
    input  logic        mst_activity,
    input  logic        slv_activity,
    input  logic        tfnf,       // TX not full
    input  logic        tfe,        // TX empty
    input  logic        rfne,       // RX not empty
    input  logic        rff,        // RX full
    input  logic        ic_en,
    input  logic        slv_activity_disabled,
    input  logic        mst_activity_disabled,

    // Interrupt status (RAW)
    input  logic [10:0] raw_intr_stat,

    // FIFO control
    input  logic [7:0]  rx_fifo_rdata,
    output logic        rx_fifo_pop,
    output logic [7:0]  tx_fifo_wdata,
    output logic        tx_fifo_push,
    output logic         tx_cmd_fifo_push,
    output logic         tx_cmd_fifo_wdata,

    // TX_ABRT source: driven from top-level (accumulated)
    input  logic [15:0] tx_abrt_source,
    output logic        tx_abrt_read_flag,

    // Interrupt
    output logic [10:0] intr,       // final masked interrupt

    // Internal write/read pulse signals
    output logic reg_write_en,
    output logic reg_read_en
);

    // ============================================================
    // APB state machine (idle/setup/access)
    // pready is always 1
    // ============================================================
    assign pready = 1'b1;

    // Write pulse: psel && pwrite && penable
    assign reg_write_en = psel && pwrite && penable;

    // Read pulse: psel && !pwrite && penable
    assign reg_read_en  = psel && !pwrite && penable;

    // ============================================================
    // Internal register declarations
    // ============================================================

    // 0x00 I2C_CON
    logic [31:0] ic_con;
    // 0x04 I2C_TAR
    logic [31:0] ic_tar_reg;
    // 0x08 I2C_SAR
    logic [31:0] ic_sar_reg;
    // 0x0C I2C_DATA_CMD (WO for write, RO for read)
    // 0x10 I2C_SS_SCL_HCNT
    logic [31:0] ic_ss_hcnt;
    // 0x14 I2C_SS_SCL_LCNT
    logic [31:0] ic_ss_lcnt;
    // 0x18 I2C_FS_SCL_HCNT
    logic [31:0] ic_fs_hcnt;
    // 0x1C I2C_FS_SCL_LCNT
    logic [31:0] ic_fs_lcnt;
    // 0x20 I2C_INTR_MASK
    logic [31:0] ic_intr_mask;
    // 0x24 I2C_INTR_STAT (RO, post-mask, = RAW & ~MASK)
    logic [31:0] ic_intr_stat;
    // 0x28 I2C_RAW_INTR_STAT (RO, pre-mask)
    logic [31:0] ic_raw_intr_stat;
    // 0x2C I2C_RX_TL
    logic [31:0] ic_rx_tl;
    // 0x30 I2C_TX_TL
    logic [31:0] ic_tx_tl;
    // 0x34 I2C_ENABLE
    logic [31:0] ic_enable;
    // 0x38 I2C_STATUS (RO, updated continuously)
    logic [31:0] ic_status;
    // 0x3C I2C_TXFLR (RO)
    logic [31:0] ic_txflr;
    // 0x40 I2C_RXFLR (RO)
    logic [31:0] ic_rxflr;
    // 0x44 I2C_SDA_HOLD
    logic [31:0] ic_sda_hold;
    // 0x48 I2C_TX_ABRT_SOURCE (RO, clr on read)
    logic [31:0] ic_tx_abrt_source;
    // 0x4C I2C_ENABLE_STATUS (RO)
    logic [31:0] ic_enable_status;

    // ============================================================
    // TX_ABRT read-to-clear flag
    // ============================================================
    always_ff @(posedge pclk or negedge presetn) begin
        if (!presetn)
            tx_abrt_read_flag <= 1'b0;
        else if (reg_read_en && (paddr == 8'h48))
            tx_abrt_read_flag <= 1'b1;
        else
            tx_abrt_read_flag <= 1'b0;
    end

    // ============================================================
    // Write Access
    // ============================================================
    always_ff @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            ic_con          <= 32'h0000_0043;  // MASTER_MODE=1, SPEED=3, RESTART_EN=1, SLAVE_DISABLE=1 (v2.1 defaults)
            ic_tar_reg      <= 32'h0;
            ic_sar_reg      <= 32'h0;
            ic_ss_hcnt      <= 32'h0000_0190;   // 400 decimal
            ic_ss_lcnt      <= 32'h0000_0190;
            ic_fs_hcnt      <= 32'h0000_003C;   // 60 decimal
            ic_fs_lcnt      <= 32'h0000_0082;   // 130 decimal
            ic_intr_mask    <= 32'h0000_03FF;   // mask all
            ic_rx_tl        <= 32'h0;
            ic_tx_tl        <= 32'h0;
            ic_enable       <= 32'h0;
            ic_sda_hold     <= 32'h0000_0001;
        end else begin
            // Default: hold values
            ic_con          <= ic_con;
            ic_tar_reg      <= ic_tar_reg;
            ic_sar_reg      <= ic_sar_reg;
            ic_ss_hcnt      <= ic_ss_hcnt;
            ic_ss_lcnt      <= ic_ss_lcnt;
            ic_fs_hcnt      <= ic_fs_hcnt;
            ic_fs_lcnt      <= ic_fs_lcnt;
            ic_intr_mask    <= ic_intr_mask;
            ic_rx_tl        <= ic_rx_tl;
            ic_tx_tl        <= ic_tx_tl;
            ic_enable       <= ic_enable;
            ic_sda_hold     <= ic_sda_hold;

            if (reg_write_en) begin
                case (paddr)
                    8'h00: ic_con          <= pwdata;
                    8'h04: ic_tar_reg      <= pwdata;
                    8'h08: ic_sar_reg      <= pwdata;
                    8'h10: ic_ss_hcnt      <= pwdata;
                    8'h14: ic_ss_lcnt      <= pwdata;
                    8'h18: ic_fs_hcnt      <= pwdata;
                    8'h1C: ic_fs_lcnt      <= pwdata;
                    8'h20: ic_intr_mask    <= pwdata;
                    // 0x24 INTR_STAT: RO, no write
                    8'h28: ic_raw_intr_stat <= pwdata;  // WC1R handled elsewhere
                    8'h2C: ic_rx_tl        <= pwdata;
                    8'h30: ic_tx_tl        <= pwdata;
                    8'h34: ic_enable       <= pwdata;
                    // 0x38 STATUS: RO, no write
                    // 0x3C TXFLR: RO, no write
                    // 0x40 RXFLR: RO, no write
                    8'h44: ic_sda_hold    <= pwdata;
                    // 0x48 TX_ABORT_SOURCE: RO, no write
                    // 0x4C ENABLE_STATUS: RO, no write
                    default: ; // read-only or reserved
                endcase
            end
        end
    end

    // ============================================================
    // DATA_CMD write: push to TX FIFOs
    // Write DATA_CMD: {CMD, DAT} → push CMD to TX_CMD_FIFO, DAT to TX_DAT_FIFO
    // ============================================================
    assign tx_fifo_wdata    = pwdata[7:0];
    assign tx_cmd_fifo_wdata = pwdata[8];
    assign tx_fifo_push     = reg_write_en && (paddr == 8'h0C);
    assign tx_cmd_fifo_push = reg_write_en && (paddr == 8'h0C);

    // ============================================================
    // Read Access
    // ============================================================
    // prdata mux
    logic [31:0] next_prdata;

    // Decode address combinationally
    // INTR_STAT = masked interrupt (post-mask)
    assign ic_intr_stat = {21'b0, raw_intr_stat & ~intr_mask};

    always_comb begin
        case (paddr)
            8'h00: next_prdata = ic_con;
            8'h04: next_prdata = ic_tar_reg;
            8'h08: next_prdata = ic_sar_reg;
            // 0x0C: read RX FIFO (RO)
            8'h10: next_prdata = ic_ss_hcnt;
            8'h14: next_prdata = ic_ss_lcnt;
            8'h18: next_prdata = ic_fs_hcnt;
            8'h1C: next_prdata = ic_fs_lcnt;
            8'h20: next_prdata = ic_intr_mask;
            8'h24: next_prdata = ic_intr_stat;     // INTR_STAT: post-mask
            8'h28: next_prdata = {21'b0, raw_intr_stat}; // RAW_INTR_STAT: pre-mask
            8'h2C: next_prdata = ic_rx_tl;
            8'h30: next_prdata = ic_tx_tl;
            8'h34: next_prdata = ic_enable;
            8'h38: next_prdata = ic_status;
            8'h3C: next_prdata = {27'b0, txflr};
            8'h40: next_prdata = {27'b0, rxflr};
            8'h44: next_prdata = ic_sda_hold;
            8'h48: next_prdata = {16'b0, tx_abrt_source};
            8'h4C: next_prdata = {29'b0, mst_activity_disabled, slv_activity_disabled, ic_en};
            default: next_prdata = 32'h0;  // undefined address returns 0
        endcase
    end

    // DATA_CMD read: return RX FIFO data
    logic [31:0] data_cmd_read_data;

    // RX FIFO pop: when reading DATA_CMD
    assign rx_fifo_pop = reg_read_en && (paddr == 8'h0C);
    assign data_cmd_read_data = {24'b0, rx_fifo_rdata};

    // prdata mux: DATA_CMD uses data_cmd_read_data, others use next_prdata
    always_comb begin
        if (reg_read_en && (paddr == 8'h0C))
            prdata = data_cmd_read_data;
        else
            prdata = next_prdata;
    end

    // ============================================================
    // Register output assignments
    // ============================================================
    assign ic_tar         = ic_tar_reg[10:0];
    assign ic_sar         = ic_sar_reg[6:0];
    assign master_mode    = ic_con[0];
    assign speed          = ic_con[2:1];
    assign restart_en     = ic_con[4];
    assign slave_disable  = ic_con[5];
    assign ss_hcnt        = ic_ss_hcnt[15:0];
    assign ss_lcnt        = ic_ss_lcnt[15:0];
    assign fs_hcnt        = ic_fs_hcnt[15:0];
    assign fs_lcnt        = ic_fs_lcnt[15:0];
    assign intr_mask      = ic_intr_mask[10:0];
    assign rx_tl          = ic_rx_tl[4:0];
    assign tx_tl          = ic_tx_tl[4:0];
    assign enable         = ic_enable[0];
    assign abort          = ic_enable[1];
    assign sda_hold       = ic_sda_hold[15:0];

    // ============================================================
    // STATUS register (read-only, computed from FIFO states)
    // ============================================================
    assign ic_status = {
        26'b0,
        slv_activity,    // [6]
        mst_activity,    // [5]
        rff,             // [4]
        rfne,            // [3]
        tfe,             // [2]
        tfnf,            // [1]
        activity         // [0]
    };

    // ============================================================
    // TX_ABRT_SOURCE read-to-clear
    // (Cleared by HW when read - managed externally)
    // ============================================================

    // ============================================================
    // INTR_MASK computation
    // intr = raw_stat & ~mask
    // ============================================================
    assign intr = raw_intr_stat & ~intr_mask;

endmodule
