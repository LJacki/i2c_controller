// i2c_ctrl_top.sv - I2C Controller Top Level
// Reference: SPEC.md v2.1
// Architecture: APB interface + Register File + 3 FIFOs + Master FSM + Slave FSM + I/O Buffer

module i2c_ctrl_top (
    // APB Interface
    input  logic        pclk,
    input  logic        presetn,
    input  logic [7:0]  paddr,
    input  logic        psel,
    input  logic        penable,
    input  logic        pwrite,
    input  logic [31:0] pwdata,
    output logic [31:0] prdata,
    output logic        pready,

    // I2C pins
    input  logic        scl_i,
    output logic        scl_o,
    output logic        scl_oe,
    input  logic        sda_i,
    output logic        sda_o,
    output logic        sda_oe,

    // Interrupt
    output logic        intr
);

    // ============================================================
    // Internal reset (active-high enable for logic)
    // presetn is async reset (active LOW)
    // We use presetn directly as rst_n (active HIGH enable)
    // ============================================================
    logic rst_n;
    assign rst_n = presetn;

    // ============================================================
    // APB Register File signals
    // ============================================================
    logic [10:0] ic_tar;
    logic [6:0]  ic_sar;
    logic        master_mode;
    logic [1:0]  speed;
    logic        restart_en;
    logic        slave_disable;
    logic [15:0] ss_hcnt, ss_lcnt;
    logic [15:0] fs_hcnt, fs_lcnt;
    logic [10:0] intr_mask;
    logic [4:0]  rx_tl, tx_tl;
    logic        enable, abort;
    logic [15:0] sda_hold;

    logic [4:0]  txflr;
    logic [4:0]  rxflr;
    logic        activity, mst_activity, slv_activity;
    logic        tfnf, tfe, rfne, rff;
    logic        ic_en;
    logic        slv_activity_disabled, mst_activity_disabled;
    logic [10:0] raw_intr_stat;
    logic        intr_loc;

    // FIFO control
    logic        rx_fifo_pop;
    logic [7:0]  tx_fifo_wdata;
    logic        tx_fifo_push;
    logic        tx_cmd_fifo_push;
    logic        tx_cmd_fifo_wdata;

    // TX CMD FIFO
    logic        tx_cmd_full, tx_cmd_empty;
    logic        tx_cmd_pop;
    logic        tx_cmd_peek;
    logic [4:0]  tx_cmd_level;

    // TX DAT FIFO
    logic        tx_dat_full, tx_dat_empty;
    logic        tx_dat_pop;
    logic [7:0]  tx_dat_rdata;
    logic [4:0]  tx_dat_level;

    // RX FIFO
    logic        rx_full, rx_empty;
    logic        rx_wr_en;
    logic        rx_overflow;
    logic [7:0]  rx_wdata;
    logic [7:0]  rx_fifo_rdata;
    logic [4:0]  rx_level;

    // TX_ABRT
    logic        tx_abrt_read_flag;

    // Master FSM signals
    logic        mst_sda_o, mst_sda_oe;
    logic        mst_start_det, mst_stop_det;
    logic        mst_rx_wr_en;
    logic [7:0]  mst_rx_wdata;
    logic        mst_tx_abrt_set;

    // Slave FSM signals
    logic        slv_sda_o, slv_sda_oe;
    logic        slv_rx_wr_en;
    logic [7:0]  slv_rx_wdata;
    logic        slv_tx_dat_rd_en;
    logic        slv_tx_dat_pop;
    logic        slv_rd_req, slv_rx_done;
    logic        slv_start_det, slv_stop_det;

    // I/O Buffer signals
    logic        scl_i_sync, sda_i_sync;

    // ============================================================
    // APB Register File
    // ============================================================
    apb_reg_file u_apb_reg (
        .pclk               (pclk),
        .presetn            (presetn),
        .paddr              (paddr),
        .psel               (psel),
        .penable            (penable),
        .pwrite             (pwrite),
        .pwdata             (pwdata),
        .prdata             (prdata),
        .pready             (pready),

        .ic_tar             (ic_tar),
        .ic_sar             (ic_sar),
        .master_mode        (master_mode),
        .speed              (speed),
        .restart_en         (restart_en),
        .slave_disable      (slave_disable),
        .ss_hcnt            (ss_hcnt),
        .ss_lcnt            (ss_lcnt),
        .fs_hcnt            (fs_hcnt),
        .fs_lcnt            (fs_lcnt),
        .intr_mask          (intr_mask),
        .rx_tl              (rx_tl),
        .tx_tl              (tx_tl),
        .enable             (enable),
        .abort              (abort),
        .sda_hold           (sda_hold),

        .txflr              (tx_dat_level),
        .rxflr              (rx_level),
        .activity           (activity),
        .mst_activity       (mst_activity),
        .slv_activity       (slv_activity),
        .tfnf               (tfnf),
        .tfe                (tfe),
        .rfne               (rfne),
        .rff                (rff),
        .ic_en              (ic_en),
        .slv_activity_disabled (slv_activity_disabled),
        .mst_activity_disabled (mst_activity_disabled),

        .raw_intr_stat      (raw_intr_stat),
        .rx_fifo_rdata      (rx_fifo_rdata),
        .rx_fifo_pop        (rx_fifo_pop),
        .tx_fifo_wdata      (tx_fifo_wdata),
        .tx_fifo_push       (tx_fifo_push),
        .tx_cmd_fifo_push   (tx_cmd_fifo_push),
        .tx_cmd_fifo_wdata  (tx_cmd_fifo_wdata),

        .tx_abrt_source     (),   // driven by top-level accumulation
        .tx_abrt_read_flag  (tx_abrt_read_flag),

        .intr               (intr_loc)
    );

    // ============================================================
    // TX CMD FIFO (16 x 1-bit)
    // ============================================================
    tx_cmd_fifo u_tx_cmd_fifo (
        .clk     (pclk),
        .rst_n   (rst_n),
        .wr_en   (tx_cmd_fifo_push),
        .rd_en   (tx_cmd_pop),      // pop after FSM consumes byte
        .cmd_i   (tx_cmd_fifo_wdata),
        .full    (tx_cmd_full),
        .empty   (tx_cmd_empty),
        .cmd_peek(tx_cmd_peek),      // peek next CMD for decision-making
        .level   (tx_cmd_level)
    );

    // ============================================================
    // TX DAT FIFO (16 x 8-bit)
    // ============================================================
    tx_dat_fifo u_tx_dat_fifo (
        .clk     (pclk),
        .rst_n   (rst_n),
        .wr_en   (tx_fifo_push),
        .rd_en   (tx_dat_pop || slv_tx_dat_pop),  // pop from Master or Slave
        .dat_i   (tx_fifo_wdata),
        .dat_o   (tx_dat_rdata),
        .full    (tx_dat_full),
        .empty   (tx_dat_empty),
        .level   (tx_dat_level)
    );

    // ============================================================
    // RX FIFO (16 x 8-bit)
    // ============================================================
    rx_fifo u_rx_fifo (
        .clk     (pclk),
        .rst_n   (rst_n),
        .wr_en   (rx_wr_en),
        .rd_en   (rx_fifo_pop),
        .dat_i   (rx_wdata),
        .dat_o   (rx_fifo_rdata),
        .full    (rx_full),
        .empty   (rx_empty),
        .overflow(rx_overflow),
        .level   (rx_level)
    );

    // Combined RX write enable (from Master OR Slave)
    assign rx_wr_en = mst_rx_wr_en || slv_rx_wr_en;
    assign rx_wdata  = mst_rx_wr_en ? mst_rx_wdata : slv_rx_wdata;

    // ============================================================
    // I/O Buffer
    // ============================================================
    // scl_i from pad → 2FF sync → scl_i_sync (for Slave FSM)
    // sda_i from pad → 2FF sync → sda_i_sync (for both FSMs)
    // scl_o, sda_o: output from Master FSM
    // scl_oe, sda_oe: output enable from Master FSM
    logic scl_meta, sda_meta;

    always_ff @(posedge pclk or negedge rst_n) begin
        if (!rst_n) begin
            scl_meta   <= 1'b1;
            scl_i_sync <= 1'b1;
            sda_meta   <= 1'b1;
            sda_i_sync <= 1'b1;
        end else begin
            scl_meta   <= scl_i;
            scl_i_sync <= scl_meta;
            sda_meta   <= sda_i;
            sda_i_sync <= sda_meta;
        end
    end

    // SDA output: Master drives in Master mode, Slave in Slave mode
    // (I2C is wired-AND; both can theoretically drive)
    assign sda_o  = master_mode ? mst_sda_o : slv_sda_o;
    assign sda_oe = (master_mode ? mst_sda_oe : 1'b0) ||
                    (!master_mode && !slave_disable ? slv_sda_oe : 1'b0);

    // SCL output: only Master drives SCL
    // (Master FSM generates scl_o internally and outputs it)
    // We use a wire to carry scl_o from Master FSM
    logic mst_scl_o;
    logic mst_scl_oe;
    assign scl_o  = mst_scl_o;
    assign scl_oe = mst_scl_oe;

    // ============================================================
    // Master FSM
    // ============================================================
    i2c_master_fsm u_master_fsm (
        .clk             (pclk),
        .rst_n           (rst_n),

        .enable          (enable),
        .abort           (abort),
        .master_mode     (master_mode),
        .restart_en      (restart_en),
        .speed           (speed),
        .tar             (ic_tar[6:0]),
        .ss_hcnt         (ss_hcnt),
        .ss_lcnt         (ss_lcnt),
        .fs_hcnt         (fs_hcnt),
        .fs_lcnt         (fs_lcnt),

        .tx_cmd_empty    (tx_cmd_empty),
        .tx_cmd_peek     (tx_cmd_peek),
        .tx_cmd_pop      (tx_cmd_pop),
        .tx_dat_empty    (tx_dat_empty),
        .tx_dat_rdata    (tx_dat_rdata),
        .tx_dat_pop      (tx_dat_pop),

        .rx_wr_en        (mst_rx_wr_en),
        .rx_wdata        (mst_rx_wdata),

        .scl_i_sync      (scl_i_sync),  // from io_buf
        .sda_i_sync      (sda_i_sync),  // from io_buf
        .sda_o           (mst_sda_o),
        .sda_oe          (mst_sda_oe),
        .scl_o           (mst_scl_o),
        .scl_oe          (mst_scl_oe),

        .mst_activity    (mst_activity),
        .start_det       (mst_start_det),
        .stop_det        (mst_stop_det),
        .tx_abrt_source  (),             // managed in top-level
        .tx_abrt_set     (mst_tx_abrt_set)
    );

    // ============================================================
    // Slave FSM
    // ============================================================
    i2c_slave_fsm u_slave_fsm (
        .clk             (pclk),
        .rst_n           (rst_n),

        .enable          (enable),
        .master_mode     (master_mode),
        .slave_disable   (slave_disable),
        .ic_sar          (ic_sar),

        .rx_wr_en        (slv_rx_wr_en),
        .rx_wdata        (slv_rx_wdata),

        .tx_dat_empty    (tx_dat_empty),
        .tx_dat_rdata    (tx_dat_rdata),
        .tx_dat_rd_en    (slv_tx_dat_rd_en),
        .tx_dat_pop      (slv_tx_dat_pop),

        .scl_i           (scl_i_sync),  // from io_buf
        .sda_i           (sda_i_sync),  // from io_buf
        .sda_o           (slv_sda_o),
        .sda_oe          (slv_sda_oe),

        .slv_activity    (slv_activity),
        .rd_req          (slv_rd_req),
        .rx_done         (slv_rx_done),
        .start_det       (slv_start_det),
        .stop_det        (slv_stop_det)
    );

    // ============================================================
    // TX_ABRT accumulation (read-to-clear)
    // ============================================================
    logic [15:0] tx_abrt_source;

    always_ff @(posedge pclk or negedge rst_n) begin
        if (!rst_n) begin
            tx_abrt_source <= 16'h0;
        end else begin
            if (tx_abrt_read_flag)
                tx_abrt_source <= 16'h0;
            else if (mst_tx_abrt_set)
                tx_abrt_source <= tx_abrt_source | 16'h0001;  // ABRT_7B_NOACK
        end
    end

    // ============================================================
    // RAW_INTR_STAT generation
    // ============================================================
    logic [10:0] raw_intr;

    assign raw_intr[10] = activity;                        // R_ACTIVITY
    assign raw_intr[9]  = mst_start_det || slv_start_det;  // R_START_DET
    assign raw_intr[8]  = mst_stop_det || slv_stop_det;    // R_STP_DET
    assign raw_intr[7]  = 1'b0;                            // R_TX_EMPTY_HLT
    assign raw_intr[6]  = slv_rd_req;                      // R_RD_REQ
    assign raw_intr[5]  = tx_dat_full && tx_fifo_push;      // R_TX_OVER
    assign raw_intr[4]  = rx_overflow;                     // R_RX_OVER
    assign raw_intr[3]  = slv_rx_done;                     // R_RX_DONE
    assign raw_intr[2]  = (tx_abrt_source != 16'h0);       // R_TX_ABRT
    assign raw_intr[1]  = (tx_dat_level <= {1'b0, tx_tl}); // R_TX_EMPTY
    assign raw_intr[0]  = (rx_level >= {1'b0, rx_tl});     // R_RX_FULL

    assign raw_intr_stat = raw_intr;

    // ============================================================
    // FIFO status signals
    // ============================================================
    assign tfnf = !tx_dat_full;
    assign tfe  = tx_dat_empty;
    assign rfne = !rx_empty;
    assign rff  = rx_full;
    assign txflr = tx_dat_level;

    assign ic_en = enable;

    assign slv_activity_disabled = slv_activity && slave_disable;
    assign mst_activity_disabled = mst_activity && !master_mode;

    // ============================================================
    // Interrupt output
    // ============================================================
    assign intr = intr_loc;

endmodule
