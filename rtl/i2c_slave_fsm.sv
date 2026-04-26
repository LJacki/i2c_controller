// i2c_slave_fsm.sv - I2C Slave FSM
// Responds to address match, receives/transmits data
// Auto ACK on address match and data byte reception
// NOTE: Clock stretching not implemented in v2.0

module i2c_slave_fsm (
    input  logic clk,
    input  logic rst_n,

    // Register controls
    input  logic        enable,
    input  logic        master_mode,
    input  logic        slave_disable,
    input  logic [6:0]  ic_sar,         // slave address

    // RX FIFO (write received data)
    output logic        rx_wr_en,
    output logic [7:0]  rx_wdata,

    // TX DAT FIFO (read for slave transmit)
    input  logic        tx_dat_empty,
    input  logic [7:0]  tx_dat_rdata,
    output logic        tx_dat_rd_en,
    output logic        tx_dat_pop,

    // I/O interface
    input  logic        scl_i,           // synchronized SCL
    input  logic        sda_i,           // synchronized SDA
    output logic        sda_o,
    output logic        sda_oe,

    // Interrupt/stauts signals
    output logic        slv_activity,
    output logic        rd_req,          // Master requested read
    output logic        rx_done,         // Slave TX ended (NACK received)
    output logic        start_det,
    output logic        stop_det
);

    // ============================================================
    // FSM state
    // ============================================================
    typedef enum logic [3:0] {
        S_IDLE       = 4'd0,   // Idle, waiting for START
        S_ADDR       = 4'd1,   // Receiving address byte
        S_ADDR_ACK   = 4'd2,   // Sending ACK after address
        S_WDATA      = 4'd3,   // Receiving data byte
        S_WACK       = 4'd4,   // Sending ACK after data received
        S_RDATA      = 4'd5,   // Transmitting data
        S_RACK       = 4'd6,   // Receiving Master ACK/NACK
        S_STRETCH    = 4'd7    // Clock stretch (v2.0: not implemented)
    } state_t;
    state_t state, next_state;

    // ============================================================
    // SDA edge detection for START/STOP
    // START: SCL=1, SDA 1→0
    // STOP:  SCL=1, SDA 0→1
    // ============================================================
    logic sda_prev;
    logic start_cond, stop_cond;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sda_prev   <= 1'b1;
        end else begin
            sda_prev <= sda_i;
        end
    end

    // Detect START/STOP when SCL is high
    assign start_cond = (scl_i == 1'b1) && (sda_prev == 1'b1) && (sda_i == 1'b0);
    assign stop_cond  = (scl_i == 1'b1) && (sda_prev == 1'b0) && (sda_i == 1'b1);

    // ============================================================
    // SCL edge detection (for bit counting and data sampling)
    // ============================================================
    logic scl_prev;
    logic scl_rising, scl_falling;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scl_prev <= 1'b1;
        end else begin
            scl_prev <= scl_i;
        end
    end

    assign scl_rising  = (scl_prev == 1'b0) && (scl_i == 1'b1);
    assign scl_falling = (scl_prev == 1'b1) && (scl_i == 1'b0);

    // ============================================================
    // Shift register for received address/data
    // ============================================================
    logic [7:0] rx_shift_reg;
    logic [7:0] tx_shift_reg;
    logic [3:0] bit_cnt;
    logic       rx_addr_valid;
    logic [6:0] received_addr;
    logic       received_rw;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_shift_reg   <= 8'h0;
            tx_shift_reg   <= 8'h0;
            bit_cnt        <= 4'd0;
            rx_addr_valid  <= 1'b0;
            received_addr  <= 7'h0;
            received_rw    <= 1'b0;
        end else begin
            case (state)
                S_IDLE: begin
                    bit_cnt <= 4'd0;
                    if (start_cond)
                        rx_addr_valid <= 1'b0;
                end

                S_ADDR: begin
                    // Shift in address on SCL rising edge
                    if (scl_rising) begin
                        rx_shift_reg <= {rx_shift_reg[6:0], sda_i};
                        if (bit_cnt < 4'd8) begin
                            bit_cnt <= bit_cnt + 1'b1;
                        end
                    end
                end

                S_ADDR_ACK: begin
                    if (scl_falling && (bit_cnt == 4'd9)) begin
                        bit_cnt <= 4'd0;
                    end
                end

                S_WDATA: begin
                    if (scl_rising) begin
                        rx_shift_reg <= {rx_shift_reg[6:0], sda_i};
                        if (bit_cnt < 4'd8) begin
                            bit_cnt <= bit_cnt + 1'b1;
                        end
                    end
                end

                S_WACK: begin
                    if (scl_falling && (bit_cnt == 4'd9)) begin
                        bit_cnt <= 4'd0;
                    end
                end

                S_RDATA: begin
                    // Shift out TX data on SCL falling edge
                    if (scl_falling) begin
                        tx_shift_reg <= {tx_shift_reg[6:0], 1'b0};
                        if (bit_cnt < 4'd8) begin
                            bit_cnt <= bit_cnt + 1'b1;
                        end
                    end
                end

                S_RACK: begin
                    if (scl_rising) begin
                        // Sample Master ACK/NACK
                        // sda_i=0 → ACK, sda_i=1 → NACK
                    end
                    if (scl_falling && (bit_cnt == 4'd9)) begin
                        bit_cnt <= 4'd0;
                    end
                end

                default: ;
            endcase
        end
    end

    // ============================================================
    // Address matching
    // ============================================================
    logic addr_match;
    assign addr_match = (received_addr == ic_sar);

    // General call address = 0x00
    logic general_call;
    assign general_call = (received_addr[6:0] == 7'h00);

    // ============================================================
    // State machine
    // ============================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= S_IDLE;
        else if (!enable)
            state <= S_IDLE;
        else
            state <= next_state;
    end

    always_comb begin
        next_state = state;
        case (state)
            S_IDLE: begin
                if (start_cond)
                    next_state = S_ADDR;
            end

            S_ADDR: begin
                // After 8 bits received, go to ACK
                if (scl_rising && (bit_cnt == 4'd7))
                    next_state = S_ADDR_ACK;
            end

            S_ADDR_ACK: begin
                // Drive ACK on 9th bit (SCL low period)
                if (scl_falling && (bit_cnt == 4'd9)) begin
                    // Check address match
                    if (addr_match || general_call) begin
                        // Address matched
                        if (received_rw == 1'b0)
                            next_state = S_WDATA;   // Master → Slave: receive data
                        else
                            next_state = S_RDATA;   // Master ← Slave: send data
                    end else begin
                        // Address not matched: go back to idle
                        next_state = S_IDLE;
                    end
                end
            end

            S_WDATA: begin
                // After 8 bits received, send ACK
                if (scl_rising && (bit_cnt == 4'd7))
                    next_state = S_WACK;
            end

            S_WACK: begin
                if (scl_falling && (bit_cnt == 4'd9)) begin
                    // Data received: push to RX FIFO
                    // Check for STOP or Repeated START
                    if (stop_cond)
                        next_state = S_IDLE;
                    else if (start_cond)
                        next_state = S_ADDR;  // Repeated START
                    else
                        next_state = S_WDATA;  // More data
                end
            end

            S_RDATA: begin
                if (scl_falling && (bit_cnt == 4'd9)) begin
                    // Pop TX FIFO data, go to RACK
                    next_state = S_RACK;
                end
            end

            S_RACK: begin
                if (scl_falling && (bit_cnt == 4'd9)) begin
                    // Master ACK? If NACK (sda_i=1), we're done
                    if (sda_i == 1'b1) begin
                        // NACK: master doesn't want more data
                        next_state = S_IDLE;
                    end else begin
                        // ACK: send next byte
                        if (!tx_dat_empty)
                            next_state = S_RDATA;
                        else
                            next_state = S_IDLE;  // TX FIFO empty, send 0x00
                    end
                end
            end

            default: next_state = S_IDLE;
        endcase
    end

    // ============================================================
    // SDA output drive
    // ============================================================
    logic sda_drive;
    logic sda_drive_en;

    always_comb begin
        case (state)
            S_ADDR_ACK: begin
                // ACK: drive SDA=0 on 9th bit
                sda_drive   = 1'b0;
                sda_drive_en = (bit_cnt >= 4'd8);  // ACK bit
            end

            S_WACK: begin
                // ACK: drive SDA=0 on 9th bit
                sda_drive   = 1'b0;
                sda_drive_en = (bit_cnt >= 4'd8);
            end

            S_RDATA: begin
                // Drive TX data on SDA
                sda_drive   = tx_shift_reg[7];  // MSB first
                sda_drive_en = 1'b1;
            end

            default: begin
                sda_drive   = 1'b1;
                sda_drive_en = 1'b0;
            end
        endcase
    end

    assign sda_o  = sda_drive;
    assign sda_oe = sda_drive_en && enable && !master_mode && !slave_disable;

    // ============================================================
    // TX FIFO pop: when TX byte consumed (at end of RACK)
    // ============================================================
    assign tx_dat_pop = (state == S_RDATA) && scl_falling && (bit_cnt == 4'd9);
    assign tx_dat_rd_en = (state == S_RDATA) && scl_falling && (bit_cnt == 4'd9);

    // ============================================================
    // RX FIFO write: when data byte fully received
    // ============================================================
    assign rx_wr_en  = (state == S_WACK) && scl_falling && (bit_cnt == 4'd9) && (addr_match || general_call);
    assign rx_wdata  = rx_shift_reg;

    // ============================================================
    // Status signals
    // ============================================================
    assign slv_activity = (state != S_IDLE);
    assign rd_req       = (state == S_RDATA) && scl_falling && (bit_cnt == 4'd9) && tx_dat_empty;
    assign rx_done      = (state == S_RACK) && scl_rising && (bit_cnt == 4'd9) && (sda_i == 1'b1);
    assign start_det    = start_cond;
    assign stop_det     = stop_cond;

    // ============================================================
    // Latch received address and R/W after address byte
    // ============================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            received_addr <= 7'h0;
            received_rw   <= 1'b0;
        end else if (state == S_ADDR_ACK && scl_falling && (bit_cnt == 4'd9)) begin
            received_addr <= rx_shift_reg[7:1];  // 7-bit address
            received_rw   <= rx_shift_reg[0];     // R/W bit
        end
    end

    // Load TX shift register from TX DAT FIFO when entering RDATA
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_shift_reg <= 8'h0;
        end else if (state == S_RDATA && bit_cnt == 4'd0) begin
            if (!tx_dat_empty)
                tx_shift_reg <= tx_dat_rdata;
            else
                tx_shift_reg <= 8'h00;  // TX FIFO empty: send 0x00
        end
    end

endmodule
