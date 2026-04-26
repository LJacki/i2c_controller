// tx_cmd_fifo.sv - TX Command FIFO (16 x 1-bit)
// Push CMD bit, pop on read request
// Synchronous reset

module tx_cmd_fifo #(
    parameter DEPTH = 16,
    parameter PTR_BITS = $clog2(DEPTH)  // 4 bits
)(
    input  logic clk,
    input  logic rst_n,   // synchronous reset (active low)
    input  logic wr_en,
    input  logic rd_en,
    input  logic cmd_i,    // 1-bit command in
    output logic full,
    output logic empty,
    output logic cmd_peek, // peek next CMD without popping
    output logic [PTR_BITS:0] level
);

    // Memory array
    logic [DEPTH-1:0] mem;

    // Read/Write pointers (binary)
    logic [PTR_BITS:0] wr_ptr;
    logic [PTR_BITS:0] rd_ptr;

    // Full/Empty/Level
    assign full  = (wr_ptr[PTR_BITS] != rd_ptr[PTR_BITS]) &&
                   (wr_ptr[PTR_BITS-1:0] == rd_ptr[PTR_BITS-1:0]);
    assign empty = (wr_ptr == rd_ptr);
    assign level = wr_ptr - rd_ptr;

    // Peek: value at current read pointer (next to be popped)
    assign cmd_peek = (!empty) ? mem[rd_ptr[PTR_BITS-1:0]] : 1'b0;

    // Write
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            wr_ptr <= '0;
        end else begin
            if (wr_en && !full) begin
                mem[wr_ptr[PTR_BITS-1:0]] <= cmd_i;
                wr_ptr <= wr_ptr + 1'b1;
            end
        end
    end

    // Read pointer advance
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            rd_ptr <= '0;
        end else if (rd_en && !empty) begin
            rd_ptr <= rd_ptr + 1'b1;
        end
    end

endmodule
