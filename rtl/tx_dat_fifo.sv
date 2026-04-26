// tx_dat_fifo.sv - TX Data FIFO (16 x 8-bit)
// Push/pop 8-bit data bytes
// Synchronous reset

module tx_dat_fifo #(
    parameter DEPTH = 16,
    parameter WIDTH = 8,
    parameter PTR_BITS = $clog2(DEPTH)  // 4 bits
)(
    input  logic clk,
    input  logic rst_n,   // synchronous reset (active low)
    input  logic wr_en,
    input  logic rd_en,
    input  logic [WIDTH-1:0] dat_i,
    output logic [WIDTH-1:0] dat_o,
    output logic full,
    output logic empty,
    output logic [PTR_BITS:0] level
);

    // Memory array
    logic [WIDTH-1:0] mem [DEPTH];

    // Read/Write pointers
    logic [PTR_BITS:0] wr_ptr;
    logic [PTR_BITS:0] rd_ptr;

    // Full/Empty/Level
    assign full  = (wr_ptr[PTR_BITS] != rd_ptr[PTR_BITS]) &&
                   (wr_ptr[PTR_BITS-1:0] == rd_ptr[PTR_BITS-1:0]);
    assign empty = (wr_ptr == rd_ptr);
    assign level = wr_ptr - rd_ptr;

    // Read output
    assign dat_o = (!empty) ? mem[rd_ptr[PTR_BITS-1:0]] : '0;

    // Write
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            wr_ptr <= '0;
        end else begin
            if (wr_en && !full) begin
                mem[wr_ptr[PTR_BITS-1:0]] <= dat_i;
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
