`timescale 1ns / 1ps

module tb_icache;
    reg clk = 1'b0;
    reg rst = 1'b1;
    always #5 clk = ~clk;

    reg inst_rreq = 1'b0;
    reg [31:0] inst_addr = 0;
    wire inst_valid;
    wire [31:0] inst_out;
    wire [3:0] cpu_ren;
    wire [31:0] cpu_raddr;
    reg dev_rvalid = 1'b0;
    reg [127:0] dev_rdata = 0;

    integer bus_reads = 0;
    integer cycles_left = 0;
    reg read_ready = 1'b0;
    wire dev_rrdy = read_ready && cycles_left == 0;
    reg [31:0] last_addr;

    ICache dut (
        .cpu_clk(clk), .cpu_rst(rst),
        .inst_rreq(inst_rreq), .inst_addr(inst_addr), .inst_valid(inst_valid), .inst_out(inst_out),
        .dev_rrdy(dev_rrdy), .cpu_ren(cpu_ren), .cpu_raddr(cpu_raddr),
        .dev_rvalid(dev_rvalid), .dev_rdata(dev_rdata)
    );

    function automatic [31:0] word_at(input reg [31:0] addr);
        word_at = 32'h91000000 | addr;
    endfunction

    always @(posedge clk) begin
        dev_rvalid <= 1'b0;
        if (rst) begin
            cycles_left <= 0;
        end else if (|cpu_ren) begin
            if (!dev_rrdy || cpu_ren !== 4'hf || cpu_raddr[3:0] !== 4'd0)
                $fatal(1, "invalid ICache line read: mask=%h address=%h", cpu_ren, cpu_raddr);
            last_addr <= cpu_raddr;
            bus_reads <= bus_reads + 1;
            cycles_left <= 3;
        end else if (cycles_left > 0) begin
            cycles_left <= cycles_left - 1;
            if (cycles_left == 1) begin
                dev_rdata <= {word_at(last_addr + 32'd12), word_at(last_addr + 32'd8),
                              word_at(last_addr + 32'd4), word_at(last_addr)};
                dev_rvalid <= 1'b1;
            end
        end
    end

    task automatic fetch(input reg [31:0] addr, input integer expected_reads);
        integer before_reads;
        @(negedge clk);
        before_reads = bus_reads;
        inst_addr = addr;
        inst_rreq = 1'b1;
        @(negedge clk);
        inst_rreq = 1'b0;
        inst_addr = 32'h00007f00;
        while (inst_valid !== 1'b1)
            @(negedge clk);
        if (inst_out !== word_at(addr) || bus_reads - before_reads != expected_reads)
            $fatal(1, "fetch %h returned %h with %0d bus reads", addr, inst_out, bus_reads - before_reads);
        if (expected_reads != 0 && last_addr !== {addr[31:4], 4'b0000})
            $fatal(1, "fetch %h requested the wrong line (%h)", addr, last_addr);
        @(negedge clk);
        if (inst_valid !== 1'b0)
            $fatal(1, "inst_valid must be a one-cycle pulse");
    endtask

    initial begin
        if ($test$plusargs("waves")) begin
            $dumpfile("tb_icache.vcd");
            $dumpvars(0, tb_icache);
        end
        repeat (2) @(negedge clk);
        rst = 1'b0;

        fork
            fetch(32'h00000124, 1);
            begin
                repeat (6) @(negedge clk);
                read_ready = 1'b1;
            end
        join
        fetch(32'h00000120, 0);
        fetch(32'h0000012c, 0);
        fetch(32'h00000528, 1); // Same index, different tag.
        fetch(32'h00000128, 1);
        fetch(32'h00000128, 0);

        rst = 1'b1;
        repeat (2) @(negedge clk);
        rst = 1'b0;
        fetch(32'h00000128, 1);
        $display("PASS ICache miss, refill, word select, conflict, and reset");
        $finish(0);
    end

    initial #10000 $fatal(1, "ICache test timed out");
endmodule
