`timescale 1ns / 1ps

// Single-port, synchronous write-first memory for 64 cache lines.
// Reset invalidates metadata while leaving the stored tag and data untouched.
module cache_line_ram (
    input  wire         clk,
    input  wire         rst,
    input  wire         we,
    input  wire [5:0]   index,
    input  wire [133:0] d,
    output wire [133:0] q
);
    reg [132:0] lines [0:63];
    reg [132:0] payload_q;
    reg [63:0] valid;
    reg valid_q;

    assign q = {valid_q, payload_q};

    always @(posedge clk) begin
        if (we && !rst) begin
            lines[index] <= d[132:0];
            payload_q    <= d[132:0];
        end else begin
            payload_q <= lines[index];
        end
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            valid   <= 64'd0;
            valid_q <= 1'b0;
        end else begin
            valid_q <= we ? d[133] : valid[index];
            if (we)
                valid[index] <= d[133];
        end
    end
endmodule
