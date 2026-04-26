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
    // HCNT/LCNT selection based on speed
    // ============================================================
    logic [15:0] hcnt, lcnt;
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
    logic [15:0] scl_cnt;
    logic        scl_cnt_en;
    logic        scl_cnt_rst;
    logic        in_high_phase;
    logic        scl_o_int;

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
                    scl_cnt       <= scl_cnt + 1'b1;
                    scl_o_int     <= 1'b0;
                end
            end else begin
                if (scl_cnt >= hcnt - 1) begin
                    scl_cnt       <= '0;
                    in_high_phase <= 1'b0;
                    scl_o_int     <= 1'b0;
                end else begin
                    scl_cnt       <= scl_cnt + 1'b1;
                    scl_o_int     <= 1'b1;
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
    logic scl_prev;
    logic scl_rising, scl_falling;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scl_prev <= 1'b1;
        end else begin
            scl_prev <= scl_o_int;
        end
    end

    assign scl_rising  = (scl_prev == 1'b0) && (scl_o_int == 1'b1);
    assign scl_falling = (scl_prev == 1'b1) && (scl_o_int == 1'b0);

    // ============================================================
    // FSM state
    // ============================================================
    typedef enum logic [3:0] {
        ST_IDLE       = 4'd0,
        ST_START      = 4'd1,   // Generate START (SDA=0 while SCL=1)
        ST_ADDR_BIT   = 4'd2,   // Send address+R/W bits (bit-by-bit)
        ST_ADDR_ACK   = 4'd3,   // Receive addr ACK/NACK
        ST_WDATA_BIT  = 4'd4,   // Send data bits
        ST_WDATA_ACK  = 4'd5,   // Receive data ACK/NACK
        ST_RDATA_BIT  = 4'd6,   // Receive data bits
        ST_RDATA_ACK  = 4'd7,   // Send ACK/NACK after receive
        ST_RESTART    = 4'd8,   // Repeated START
        ST_STOP       = 4'd9    // Generate STOP
    } state_t;
    state_t state, next_state;

    // ============================================================
    // Current and next CMD/DAT holding registers
    // ============================================================
    logic       cur_cmd;       // 0=write, 1=read
    logic [7:0] cur_dat;
    logic       have_cur;      // cur_cmd/dat are valid

    logic       nxt_cmd;
    logic [7:0] nxt_dat;
    logic       have_nxt;

    // Peek at next CMD without consuming
    logic       peek_cmd;
    assign peek_cmd = tx_cmd_peek;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cur_cmd  <= 1'b0;
            cur_dat  <= 8'h0;
            have_cur <= 1'b0;
            nxt_cmd  <= 1'b0;
            nxt_dat  <= 8'h0;
            have_nxt <= 1'b0;
        end else begin
            case (state)
                ST_IDLE: begin
                    // Load first CMD/DAT when transitioning out of IDLE
                    if (next_state != ST_IDLE && enable && master_mode) begin
                        cur_cmd  <= tx_cmd_peek;   // peek CMD
                        cur_dat  <= tx_dat_rdata;
                        have_cur <= 1'b1;
                    end
                end

                // Load next CMD/DAT at end of ACK phase
                ST_ADDR_ACK, ST_WDATA_ACK, ST_RDATA_ACK: begin
                    if (scl_falling && (bit_cnt == 4'd9)) begin
                        if (have_nxt) begin
                            cur_cmd  <= nxt_cmd;
                            cur_dat  <= nxt_dat;
                            have_cur <= 1'b1;
                            have_nxt <= 1'b0;
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
    logic pop_at_ack;
    logic [7:0] tx_byte;

    // Address byte: TAR[6:0] + R/W
    assign tx_byte = (state == ST_ADDR_BIT) ? {tar[6:0], cur_cmd} : cur_dat;

    // Pop current CMD/DAT at ACK phase end
    assign tx_cmd_pop = pop_at_ack;
    assign tx_dat_pop = pop_at_ack;

    // Load next CMD/DAT from FIFO into nxt_cmd/nxt_dat
    // (done at the same ACK phase end)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            have_nxt <= 1'b0;
            nxt_cmd  <= 1'b0;
            nxt_dat  <= 8'h0;
        end else begin
            // Clear have_nxt when cur_cmd is consumed (pop_at_ack)
            if (pop_at_ack) begin
                have_nxt <= 1'b0;
            end
            // Load next when FIFO has data
            if (load_nxt) begin
                nxt_cmd  <= tx_cmd_peek;
                nxt_dat  <= tx_dat_rdata;
                have_nxt <= 1'b1;
            end
        end
    end

    // ============================================================
    // Bit counter and shift register
    // ============================================================
    logic [3:0] bit_cnt;
    logic [7:0] tx_shift;
    logic [7:0] rx_shift;
    logic       slave_ack;      // 0=ACK, 1=NACK

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

                // Count bits on SCL falling edges
                ST_ADDR_BIT: begin
                    if (scl_falling) begin
                        tx_shift <= {tx_shift[6:0], 1'b0};  // MSB first
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
                    end
                    if (scl_falling) begin
                        bit_cnt <= bit_cnt + 1'b1;
                    end
                end

                ST_RDATA_ACK: begin
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
    logic sda_drive;
    logic sda_drive_en;

    // MSB-first: which bit of tx_shift is on the wire?
    logic tx_bit;
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
                // START: SDA=0 while SCL=1
                sda_drive = 1'b0; sda_drive_en = 1'b1;
            end

            ST_ADDR_BIT, ST_WDATA_BIT: begin
                sda_drive = tx_bit; sda_drive_en = 1'b1;
            end

            // ACK bit (bit 8): drive ACK=0
            ST_ADDR_ACK, ST_WDATA_ACK: begin
                sda_drive   = (bit_cnt == 4'd8) ? 1'b0 : 1'b1;
                sda_drive_en = (bit_cnt >= 4'd8);
            end

            // Release SDA for slave to drive during read
            ST_RDATA_BIT: begin
                sda_drive = 1'b1; sda_drive_en = 1'b0;
            end

            // ACK/NACK: ACK=0 (more reads), NACK=1 (last read)
            ST_RDATA_ACK: begin
                if (bit_cnt == 4'd8) begin
                    if (more_reads_after_this)
                        sda_drive = 1'b0;  // ACK: more data coming
                    else
                        sda_drive = 1'b1;  // NACK: last byte
                end else begin
                    sda_drive = 1'b1;
                end
                sda_drive_en = (bit_cnt >= 4'd8);
            end

            ST_RESTART: begin
                // Repeated START: SDA=0 while SCL=1
                sda_drive = 1'b0; sda_drive_en = 1'b1;
            end

            ST_STOP: begin
                // STOP: drive SDA=0 first (then 0→1 transition at next SCL high)
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
    logic scl_cnt_en_p1;  // registered version
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
    logic load_nxt;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pop_at_ack <= 1'b0;
            load_nxt    <= 1'b0;
        end else begin
            pop_at_ack <= 1'b0;
            load_nxt    <= 1'b0;

            // At end of ACK phase: pop current, load next if available
            if (((state == ST_ADDR_ACK) || (state == ST_WDATA_ACK) || (state == ST_RDATA_ACK))
                && scl_falling && (bit_cnt == 4'd9)) begin
                pop_at_ack <= 1'b1;
                if (!tx_cmd_empty && !tx_dat_empty) begin
                    load_nxt <= 1'b1;
                end
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
    // Combinational: which abort condition is active
    logic abrt_noack_addr;
    logic abrt_noack_data;
    assign abrt_noack_addr = (state == ST_ADDR_ACK) && scl_rising && (bit_cnt == 4'd9) && slave_ack;
    assign abrt_noack_data = (state == ST_WDATA_ACK) && scl_rising && (bit_cnt == 4'd9) && slave_ack;

    assign tx_abrt_source = {
        12'b0,
        abrt_noack_data,  // [3] ABRT_TXDATA_NOACK
        1'b0, 1'b0,        // [2:1] 10-bit addr NACKs
        abrt_noack_addr,  // [0] ABRT_7B_NOACK
        1'b0              // upper bits
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
            state <= ST_STOP;  // Abort: send STOP
        else
            state <= next_state;
    end

    // ============================================================
    // Next CMD/Data lookahead (for decision making)
    // ============================================================
    // In WDATA_BIT/WDATA_ACK: decide what to do after ACK
    // In RDATA_BIT/RDATA_ACK: decide ACK vs NACK
    logic more_writes_after_this;   // more CMD=0 after this byte
    logic more_reads_after_this;    // more CMD=1 after this byte
    logic will_restart_write_to_read;  // this byte CMD=0, next byte CMD=1
    logic tx_fifo_has_more;         // at least one more CMD/DAT pair in FIFO

    assign tx_fifo_has_more = !tx_cmd_empty && !tx_dat_empty;

    // Note: peek_cmd reflects the NEXT entry in TX CMD FIFO
    // After current byte: if more data in FIFO, peek it
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
                if (in_high_phase && (scl_cnt == '0))
                    next_state = ST_ADDR_BIT;
            end

            ST_ADDR_BIT: begin
                if (scl_falling && (bit_cnt == 4'd9))
                    next_state = ST_ADDR_ACK;
            end

            ST_ADDR_ACK: begin
                if (scl_falling && (bit_cnt == 4'd9)) begin
                    if (!slave_ack) begin
                        next_state = ST_STOP;  // NACK: abort
                    end else if (cur_cmd == 1'b0) begin
                        next_state = ST_WDATA_BIT;
                    end else begin
                        next_state = ST_RDATA_BIT;
                    end
                end
            end

            ST_WDATA_BIT: begin
                if (scl_falling && (bit_cnt == 4'd9))
                    next_state = ST_WDATA_ACK;
            end

            ST_WDATA_ACK: begin
                if (scl_falling && (bit_cnt == 4'd9)) begin
                    if (!slave_ack) begin
                        next_state = ST_STOP;  // NACK
                    end else if (more_writes_after_this) begin
                        next_state = ST_WDATA_BIT;  // continue writing
                    end else if (will_restart_write_to_read && restart_en) begin
                        next_state = ST_RESTART;    // Write→Read: Repeated START
                    end else begin
                        next_state = ST_STOP;       // STOP
                    end
                end
            end

            ST_RDATA_BIT: begin
                if (scl_falling && (bit_cnt == 4'd9))
                    next_state = ST_RDATA_ACK;
            end

            ST_RDATA_ACK: begin
                if (scl_falling && (bit_cnt == 4'd9)) begin
                    if (more_reads_after_this) begin
                        next_state = ST_RDATA_BIT;  // more reads: ACK, continue
                    end else begin
                        next_state = ST_STOP;  // last read: NACK then STOP
                    end
                end
            end

            ST_RESTART: begin
                if (in_high_phase && (scl_cnt == '0))
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
    // Status signals
    // ============================================================
    assign mst_activity = (state != ST_IDLE);
    assign start_det = (state == ST_START) && in_high_phase && (scl_cnt == '0);
    assign stop_det  = (state == ST_STOP)  && in_high_phase && (scl_cnt >= hcnt - 1);

endmodule
