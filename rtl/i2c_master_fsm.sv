// i2c_master_fsm.sv - I2C Master FSM
// Reference: SPEC.md v2.1 Section 10
// Protocol: START→ADDR+R/W→[DATA bytes]→ACK/NACK→STOP/RepeatedSTART

module i2c_master_fsm (
    input  logic clk,
    input  logic rst_n,

    // Register controls
    input  logic        enable,
    input  logic        abort,
    input  logic        master_mode,
    input  logic        restart_en,
    input  logic [1:0] speed,          // 1=SS, 2=FS, 3=FS+
    input  logic [6:0]  tar,            // 7-bit target address
    input  logic [15:0] ss_hcnt,
    input  logic [15:0] ss_lcnt,
    input  logic [15:0] fs_hcnt,
    input  logic [15:0] fs_lcnt,

    // TX CMD FIFO (1-bit)
    input  logic        tx_cmd_empty,
    input  logic        tx_cmd_peek,    // peek next CMD without popping
    output logic        tx_cmd_pop,     // pop CMD after byte consumed

    // TX DAT FIFO (8-bit)
    input  logic        tx_dat_empty,
    input  logic [7:0] tx_dat_rdata,
    output logic        tx_dat_pop,     // pop DAT after byte consumed

    // RX FIFO (write received data)
    output logic        rx_wr_en,
    output logic [7:0]  rx_wdata,

    // I/O interface
    input  logic        scl_i_sync,     // synchronized SCL
    input  logic        sda_i_sync,     // synchronized SDA
    output logic        sda_o,
    output logic        sda_oe,
    output logic        scl_o,          // generated SCL clock
    output logic        scl_oe,         // SCL output enable

    // Status/interrupt signals
    output logic        mst_activity,
    output logic        start_det,
    output logic        stop_det,
    output logic [15:0] tx_abrt_source, // abort source flags (combinational)
    output logic        tx_abrt_set     // abort detected (pulse)
);

    // ============================================================
    // Internal signal declarations (module scope - all declared before use)
    // ============================================================
    // HCNT/LCNT selection based on speed
    logic [15:0] hcnt, lcnt;
    // SCL clock generation
    logic [15:0] scl_cnt;
    logic        scl_cnt_en;
    logic        scl_cnt_rst;
    logic        in_high_phase;
    logic        scl_o_int;
    // SCL edge detection
    logic        scl_prev;
    logic        scl_rising, scl_falling;
    // FSM state
    typedef enum logic [3:0] {
        ST_IDLE       = 4'd0,
        ST_START      = 4'd1,
        ST_ADDR_BIT   = 4'd2,
        ST_ADDR_ACK   = 4'd3,
        ST_WDATA_BIT  = 4'd4,
        ST_WDATA_ACK  = 4'd5,
        ST_RDATA_BIT  = 4'd6,
        ST_RDATA_ACK  = 4'd7,
        ST_RESTART    = 4'd8,
        ST_STOP       = 4'd9
    } state_t;
    state_t state, next_state;
    // CMD/DAT holding registers
    logic       cur_cmd;
    logic [7:0] cur_dat;
    logic       have_cur;
    logic       nxt_cmd;
    logic [7:0] nxt_dat;
    logic       have_nxt;
    logic       peek_cmd;
    // TX byte construction and FIFO pop
    logic       pop_at_ack;
    logic [7:0] tx_byte;
    // Bit counter and shift register
    logic [3:0] bit_cnt;
    logic [7:0] tx_shift;
    logic [7:0] rx_shift;
    logic       slave_ack;
    // SDA output drive
    logic       sda_drive;
    logic       sda_drive_en;
    logic       tx_bit;
    // SCL counter control
    logic       scl_cnt_en_p1;
    // Pop and load signals
    logic       load_nxt;
    // TX_ABRT source
    logic       abrt_noack_addr;
    logic       abrt_noack_data;
    // FIFO lookahead
    logic       more_writes_after_this;
    logic       more_reads_after_this;
    logic       will_restart_write_to_read;
    logic       tx_fifo_has_more;

    // ============================================================
    // HCNT/LCNT selection based on speed
    // ============================================================
    always_comb begin
        case (speed)
            2'b01: begin hcnt = {1'b0, ss_hcnt[14:0]}; lcnt = {1'b0, ss_lcnt[14:0]}; end
            2'b10, 2'b11: begin hcnt = {1'b0, fs_hcnt[14:0]}; lcnt = {1'b0, fs_lcnt[14:0]}; end
            default: begin hcnt = {1'b0, fs_hcnt[14:0]}; lcnt = {1'b0, fs_lcnt[14:0]}; end
        endcase
    end

    // ============================================================
    // SCL clock generator
    // Generates scl_o: hcnt cycles high, lcnt cycles low, repeat
    // scl_o_idle = 1 (I2C idle = SCL high)
    // ============================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scl_cnt       <= '0;
            in_high_phase <= 1'b1;
            scl_o_int     <= 1'b1;
        end else if (scl_cnt_rst) begin
            scl_cnt       <= '0;
            in_high_phase <= 1'b1;
            scl_o_int     <= 1'b1;
        end else if (scl_cnt_en) begin
            if (!in_high_phase) begin
                if (scl_cnt >= lcnt - 1) begin
                    scl_cnt       <= '0;
                    in_high_phase <= 1'b1;
                    scl_o_int     <= 1'b1;
                end else begin
                    scl_cnt   <= scl_cnt + 1'b1;
                    scl_o_int <= 1'b0;
                end
            end else begin
                if (scl_cnt >= hcnt - 1) begin
                    scl_cnt       <= '0;
                    in_high_phase <= 1'b0;
                    scl_o_int     <= 1'b0;
                end else begin
                    scl_cnt   <= scl_cnt + 1'b1;
                    scl_o_int <= 1'b1;
                end
            end
        end else begin
            scl_o_int     <= 1'b1;
            in_high_phase <= 1'b1;
        end
    end

    assign scl_o  = scl_o_int;
    assign scl_oe = scl_cnt_en && enable && master_mode;

    // ============================================================
    // SCL edge detection (using scl_o_int which is pclk-synchronous)
    // ============================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            scl_prev <= 1'b1;
        else
            scl_prev <= scl_o_int;
    end

    assign scl_rising  = (scl_prev == 1'b0) && (scl_o_int == 1'b1);
    assign scl_falling = (scl_prev == 1'b1) && (scl_o_int == 1'b0);

    // ============================================================
    // Current CMD/DAT holding register
    // ============================================================
    assign peek_cmd = tx_cmd_peek;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cur_cmd  <= 1'b0;
            cur_dat  <= 8'h0;
            have_cur <= 1'b0;
        end else begin
            case (state)
                ST_IDLE: begin
                    if (next_state != ST_IDLE && enable && master_mode) begin
                        cur_cmd  <= tx_cmd_peek;
                        cur_dat  <= tx_dat_rdata;
                        have_cur <= 1'b1;
                    end
                end

                ST_ADDR_ACK, ST_WDATA_ACK, ST_RDATA_ACK: begin
                    if (scl_falling && (bit_cnt == 4'd9)) begin
                        if (have_nxt) begin
                            cur_cmd  <= nxt_cmd;
                            cur_dat  <= nxt_dat;
                            have_cur <= 1'b1;
                        end else begin
                            have_cur <= 1'b0;
                        end
                    end
                end

                default: ;
            endcase
        end
    end

    // ============================================================
    // TX CMD/DAT FIFO pop (at end of byte transaction)
    // ============================================================
    assign tx_byte    = (state == ST_ADDR_BIT) ? {tar[6:0], cur_cmd} : cur_dat;
    assign tx_cmd_pop = pop_at_ack;
    assign tx_dat_pop = pop_at_ack;

    // Load next CMD/DAT from FIFO into nxt_cmd/nxt_dat
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            have_nxt <= 1'b0;
            nxt_cmd  <= 1'b0;
            nxt_dat  <= 8'h0;
        end else begin
            if (pop_at_ack) begin
                have_nxt <= 1'b0;
            end else if (load_nxt) begin
                nxt_cmd  <= tx_cmd_peek;
                nxt_dat  <= tx_dat_rdata;
                have_nxt <= 1'b1;
            end
        end
    end

    // ============================================================
    // Bit counter and shift register
    // ============================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bit_cnt    <= 4'd0;
            tx_shift   <= 8'h0;
            rx_shift   <= 8'h0;
            slave_ack  <= 1'b0;
        end else begin
            case (state)
                ST_IDLE: begin
                    bit_cnt  <= 4'd0;
                    rx_shift <= 8'h0;
                end

                ST_START: begin
                    bit_cnt <= 4'd0;
                end

                ST_ADDR_BIT: begin
                    if (scl_falling) begin
                        tx_shift <= {tx_shift[6:0], 1'b0};
                        bit_cnt  <= bit_cnt + 1'b1;
                    end
                end

                ST_ADDR_ACK: begin
                    if (scl_rising && (bit_cnt == 4'd9))
                        slave_ack <= sda_i_sync;
                    if (scl_falling) begin
                        if (bit_cnt < 4'd9)
                            bit_cnt <= bit_cnt + 1'b1;
                        else
                            bit_cnt <= 4'd0;
                    end
                end

                ST_WDATA_BIT: begin
                    if (scl_falling) begin
                        tx_shift <= {tx_shift[6:0], 1'b0};
                        bit_cnt  <= bit_cnt + 1'b1;
                    end
                end

                ST_WDATA_ACK: begin
                    if (scl_rising && (bit_cnt == 4'd9))
                        slave_ack <= sda_i_sync;
                    if (scl_falling) begin
                        if (bit_cnt < 4'd9)
                            bit_cnt <= bit_cnt + 1'b1;
                        else
                            bit_cnt <= 4'd0;
                    end
                end

                ST_RDATA_BIT: begin
                    if (scl_rising) begin
                        rx_shift <= {rx_shift[6:0], sda_i_sync};
                        bit_cnt  <= bit_cnt + 1'b1;
                    end
                end

                ST_RDATA_ACK: begin
                    if (scl_rising && (bit_cnt == 4'd9))
                        slave_ack <= sda_i_sync;
                    if (scl_falling) begin
                        if (bit_cnt < 4'd9)
                            bit_cnt <= bit_cnt + 1'b1;
                        else
                            bit_cnt <= 4'd0;
                    end
                end

                default: ;
            endcase
        end
    end

    // ============================================================
    // SDA output drive
    // ============================================================
    always_comb begin
        if ((state == ST_ADDR_BIT) || (state == ST_WDATA_BIT))
            tx_bit = tx_shift[7];
        else
            tx_bit = 1'b1;
    end

    always_comb begin
        case (state)
            ST_IDLE: begin
                sda_drive = 1'b1; sda_drive_en = 1'b0;
            end

            ST_START: begin
                sda_drive = 1'b0; sda_drive_en = 1'b1;
            end

            ST_ADDR_BIT, ST_WDATA_BIT: begin
                sda_drive = tx_bit; sda_drive_en = 1'b1;
            end

            ST_ADDR_ACK, ST_WDATA_ACK: begin
                sda_drive   = (bit_cnt == 4'd8) ? 1'b0 : 1'b1;
                sda_drive_en = (bit_cnt >= 4'd8);
            end

            ST_RDATA_BIT: begin
                sda_drive = 1'b1; sda_drive_en = 1'b0;
            end

            ST_RDATA_ACK: begin
                if (bit_cnt == 4'd8) begin
                    if (more_reads_after_this)
                        sda_drive = 1'b0;
                    else
                        sda_drive = 1'b1;
                end else begin
                    sda_drive = 1'b1;
                end
                sda_drive_en = (bit_cnt >= 4'd8);
            end

            ST_RESTART: begin
                sda_drive = 1'b0; sda_drive_en = 1'b1;
            end

            ST_STOP: begin
                sda_drive = 1'b0; sda_drive_en = 1'b1;
            end

            default: begin
                sda_drive = 1'b1; sda_drive_en = 1'b0;
            end
        endcase
    end

    assign sda_o  = sda_drive;
    assign sda_oe = sda_drive_en && enable && master_mode;

    // ============================================================
    // SCL counter control
    // ============================================================
    always_comb begin
        case (state)
            ST_IDLE:    scl_cnt_en = 1'b0;
            ST_START,
            ST_ADDR_BIT, ST_ADDR_ACK,
            ST_WDATA_BIT, ST_WDATA_ACK,
            ST_RDATA_BIT, ST_RDATA_ACK,
            ST_RESTART, ST_STOP: begin
                scl_cnt_en = enable && master_mode;
            end
            default:    scl_cnt_en = 1'b0;
        endcase
    end

    always_ff @(posedge clk) begin
        scl_cnt_en_p1 <= scl_cnt_en;
        scl_cnt_rst   <= (state == ST_IDLE) && !enable;
    end

    // ============================================================
    // Pop and load signals
    // ============================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pop_at_ack <= 1'b0;
            load_nxt   <= 1'b0;
        end else begin
            pop_at_ack <= 1'b0;
            load_nxt   <= 1'b0;

            if (((state == ST_ADDR_ACK) || (state == ST_WDATA_ACK) || (state == ST_RDATA_ACK))
                && scl_falling && (bit_cnt == 4'd9)) begin
                pop_at_ack <= 1'b1;
                if (!tx_cmd_empty && !tx_dat_empty)
                    load_nxt <= 1'b1;
            end
        end
    end

    // ============================================================
    // RX FIFO write (after receiving a data byte)
    // ============================================================
    assign rx_wr_en  = (state == ST_RDATA_ACK) && scl_falling && (bit_cnt == 4'd9);
    assign rx_wdata  = rx_shift;

    // ============================================================
    // TX_ABRT source
    // ============================================================
    assign abrt_noack_addr = (state == ST_ADDR_ACK) && scl_rising && (bit_cnt == 4'd9) && slave_ack;
    assign abrt_noack_data = (state == ST_WDATA_ACK) && scl_rising && (bit_cnt == 4'd9) && slave_ack;

    assign tx_abrt_source = {
        12'b0,
        abrt_noack_data,  // [3] ABRT_TXDATA_NOACK
        1'b0, 1'b0,      // [2:1] 10-bit addr NACKs
        abrt_noack_addr,  // [0] ABRT_7B_NOACK
        1'b0
    };

    assign tx_abrt_set = abrt_noack_addr || abrt_noack_data;

    // ============================================================
    // State register
    // ============================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= ST_IDLE;
        else if (!enable)
            state <= ST_IDLE;
        else if (abort)
            state <= ST_STOP;
        else
            state <= next_state;
    end

    // ============================================================
    // FIFO lookahead
    // ============================================================
    assign tx_fifo_has_more = !tx_cmd_empty && !tx_dat_empty;
    assign more_writes_after_this  = tx_fifo_has_more && (peek_cmd == 1'b0);
    assign more_reads_after_this   = tx_fifo_has_more && (peek_cmd == 1'b1);
    assign will_restart_write_to_read = (have_nxt && (nxt_cmd == 1'b1)) ||
                                        (!have_nxt && tx_fifo_has_more && (peek_cmd == 1'b1));

    // ============================================================
    // Next state logic
    // ============================================================
    always_comb begin
        next_state = state;
        case (state)
            ST_IDLE: begin
                if (enable && master_mode && !tx_cmd_empty && !tx_dat_empty)
                    next_state = ST_START;
            end

            ST_START: begin
                if (in_high_phase && (scl_cnt == 16'b0))
                    next_state = ST_ADDR_BIT;
            end

            ST_ADDR_BIT: begin
                if (scl_falling && (bit_cnt == 4'd9))
                    next_state = ST_ADDR_ACK;
            end

            ST_ADDR_ACK: begin
                if (scl_falling && (bit_cnt == 4'd9)) begin
                    if (!slave_ack)
                        next_state = ST_STOP;
                    else if (cur_cmd == 1'b0)
                        next_state = ST_WDATA_BIT;
                    else
                        next_state = ST_RDATA_BIT;
                end
            end

            ST_WDATA_BIT: begin
                if (scl_falling && (bit_cnt == 4'd9))
                    next_state = ST_WDATA_ACK;
            end

            ST_WDATA_ACK: begin
                if (scl_falling && (bit_cnt == 4'd9)) begin
                    if (!slave_ack)
                        next_state = ST_STOP;
                    else if (more_writes_after_this)
                        next_state = ST_WDATA_BIT;
                    else if (will_restart_write_to_read && restart_en)
                        next_state = ST_RESTART;
                    else
                        next_state = ST_STOP;
                end
            end

            ST_RDATA_BIT: begin
                if (scl_falling && (bit_cnt == 4'd9))
                    next_state = ST_RDATA_ACK;
            end

            ST_RDATA_ACK: begin
                if (scl_falling && (bit_cnt == 4'd9)) begin
                    if (more_reads_after_this)
                        next_state = ST_RDATA_BIT;
                    else
                        next_state = ST_STOP;
                end
            end

            ST_RESTART: begin
                if (in_high_phase && (scl_cnt == 16'b0))
                    next_state = ST_ADDR_BIT;
            end

            ST_STOP: begin
                if (in_high_phase && (scl_cnt >= hcnt - 1))
                    next_state = ST_IDLE;
            end

            default: next_state = ST_IDLE;
        endcase
    end

    // ============================================================
    // Status and interrupt signals
    // ============================================================
    assign mst_activity = (state != ST_IDLE);
    assign start_det = (state == ST_START) && in_high_phase && (scl_cnt == 16'b0);
    assign stop_det  = (state == ST_STOP)  && in_high_phase && (scl_cnt >= hcnt - 1);

endmodule : i2c_master_fsm
