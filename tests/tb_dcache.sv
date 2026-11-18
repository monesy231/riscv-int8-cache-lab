`timescale 1ns / 1ps

module tb_dcache;
    reg clk = 1'b0;
    reg rst = 1'b1;
    always #5 clk = ~clk;

    reg [3:0] data_ren = 0, data_wen = 0;
    reg [31:0] data_addr = 0, data_wdata = 0;
    wire [31:0] data_rdata;
    wire data_valid, data_wresp;
    wire [3:0] cpu_ren, cpu_wen;
    wire [31:0] cpu_raddr, cpu_waddr, cpu_wdata;

    localparam [31:0] CACHED = 32'h00000034;
    localparam [31:0] CONFLICT = 32'h00000434;
    localparam [31:0] MMIO = 32'hffff0034;
    reg [31:0] memory [0:8191];
    reg [31:0] peripheral = 32'h80102030;
    reg [127:0] read_buffer;
    reg [127:0] dev_rdata = 0;
    reg dev_rvalid = 1'b0;
    reg allow_reads = 1'b1, allow_writes = 1'b1;
    integer read_delay = 0, write_delay = 0;
    wire dev_rrdy = allow_reads && read_delay == 0;
    wire dev_wrdy = allow_writes && write_delay == 0;
    integer bus_reads = 0, bus_writes = 0;
    reg [31:0] last_raddr, last_waddr, last_wdata;
    reg [3:0] last_ren, last_wen;

    DCache dut (
        .cpu_clk(clk), .cpu_rst(rst), .data_ren(data_ren), .data_addr(data_addr),
        .data_valid(data_valid), .data_rdata(data_rdata), .data_wen(data_wen),
        .data_wdata(data_wdata), .data_wresp(data_wresp),
        .dev_wrdy(dev_wrdy), .cpu_wen(cpu_wen), .cpu_waddr(cpu_waddr), .cpu_wdata(cpu_wdata),
        .dev_rrdy(dev_rrdy), .cpu_ren(cpu_ren), .cpu_raddr(cpu_raddr),
        .dev_rvalid(dev_rvalid), .dev_rdata(dev_rdata)
    );

    always @(posedge clk) begin
        dev_rvalid <= 1'b0;
        if (rst) begin
            read_delay <= 0;
            write_delay <= 0;
        end else begin
            if (|cpu_ren) begin
                if (!dev_rrdy)
                    $fatal(1, "DCache issued a read while the device was busy");
                last_raddr <= cpu_raddr;
                last_ren <= cpu_ren;
                bus_reads <= bus_reads + 1;
                read_delay <= 3;
                if (cpu_raddr == MMIO) begin
                    read_buffer <= {96'd0, peripheral};
                end else begin
                    if (cpu_ren !== 4'hf || cpu_raddr[31:15] !== 17'd0 || cpu_raddr[3:0] !== 4'd0)
                        $fatal(1, "invalid DCache line read: mask=%h address=%h", cpu_ren, cpu_raddr);
                    read_buffer <= {memory[cpu_raddr[14:2] + 3], memory[cpu_raddr[14:2] + 2],
                                    memory[cpu_raddr[14:2] + 1], memory[cpu_raddr[14:2]]};
                end
            end else if (read_delay > 0) begin
                read_delay <= read_delay - 1;
                if (read_delay == 1) begin
                    dev_rdata <= read_buffer;
                    dev_rvalid <= 1'b1;
                end
            end

            if (|cpu_wen) begin
                if (!dev_wrdy)
                    $fatal(1, "DCache issued a write while the device was busy");
                last_waddr <= cpu_waddr;
                last_wdata <= cpu_wdata;
                last_wen <= cpu_wen;
                bus_writes <= bus_writes + 1;
                write_delay <= 3;
                for (integer lane = 0; lane < 4; lane = lane + 1) begin
                    if (cpu_wen[lane]) begin
                        if (cpu_waddr == MMIO)
                            peripheral[8*lane +: 8] <= cpu_wdata[8*lane +: 8];
                        else
                            memory[cpu_waddr[14:2]][8*lane +: 8] <= cpu_wdata[8*lane +: 8];
                    end
                end
            end else if (write_delay > 0) begin
                write_delay <= write_delay - 1;
            end
        end
    end

    task automatic read_word(input reg [31:0] addr, input reg [3:0] enable,
                             input reg [31:0] expected, input integer expected_reads);
        integer before_reads;
        @(negedge clk);
        before_reads = bus_reads;
        data_addr = addr;
        data_ren = enable;
        @(negedge clk);
        while (data_valid !== 1'b1)
            @(negedge clk);
        if (data_rdata !== expected || bus_reads - before_reads != expected_reads)
            $fatal(1, "read %h returned %h with %0d bus reads", addr, data_rdata, bus_reads - before_reads);
        if (addr == MMIO && (last_raddr !== addr || last_ren !== enable))
            $fatal(1, "MMIO read did not preserve address and mask");

        // Keep the request high after the response, as a stalled CPU might.
        repeat (4) begin
            @(negedge clk);
            if (data_valid !== 1'b0 || bus_reads - before_reads != expected_reads)
                $fatal(1, "DCache accepted the same held read twice");
        end
        data_ren = 0;
        @(negedge clk);
    endtask

    task automatic write_word(input reg [31:0] addr, value, input reg [3:0] enable);
        integer before_reads, before_writes;
        @(negedge clk);
        before_reads = bus_reads;
        before_writes = bus_writes;
        data_addr = addr;
        data_wdata = value;
        data_wen = enable;
        @(negedge clk);
        data_wen = 0;
        data_addr = 32'h00007f00;
        data_wdata = 0;
        while (data_wresp !== 1'b1)
            @(negedge clk);
        if (!dev_wrdy || bus_writes - before_writes != 1 || bus_reads != before_reads ||
            last_waddr !== addr || last_wen !== enable || last_wdata !== value)
            $fatal(1, "write %h did not complete with the expected bus transaction", addr);
        @(negedge clk);
        if (data_wresp !== 1'b0)
            $fatal(1, "data_wresp must be a one-cycle pulse");
    endtask

    initial begin
        if ($test$plusargs("waves")) begin
            $dumpfile("tb_dcache.vcd");
            $dumpvars(0, tb_dcache);
        end
        for (integer i = 0; i < 8192; i = i + 1)
            memory[i] = 32'h99000000 | i;
        memory[CACHED[14:2]] = 32'h11223344;
        repeat (2) @(negedge clk);
        rst = 1'b0;

        read_word(CACHED, 4'hf, 32'h11223344, 1);
        read_word(CACHED + 32'd8, 4'h1, 32'h9900000f, 0);
        allow_writes = 1'b0;
        fork
            write_word(CACHED, 32'haabbccdd, 4'b0101);
            begin
                repeat (6) @(negedge clk);
                allow_writes = 1'b1;
            end
        join
        if (memory[CACHED[14:2]] !== 32'h11bb33dd)
            $fatal(1, "write hit did not update backing memory by byte mask");
        read_word(CACHED, 4'hf, 32'h11bb33dd, 0);

        write_word(CONFLICT, 32'h12345678, 4'hf);
        read_word(CACHED, 4'hf, 32'h11bb33dd, 0); // Write miss leaves the old line.
        read_word(CONFLICT, 4'hf, 32'h12345678, 1);
        read_word(CACHED, 4'hf, 32'h11bb33dd, 1);

        allow_reads = 1'b0;
        fork
            read_word(MMIO, 4'h3, 32'h80102030, 1);
            begin
                repeat (5) @(negedge clk);
                allow_reads = 1'b1;
            end
        join
        write_word(MMIO, 32'hffccbbaa, 4'h8);
        read_word(MMIO, 4'h8, 32'hff102030, 1);
        read_word(CACHED, 4'hf, 32'h11bb33dd, 0);

        $display("PASS DCache refill, write-through, no-write-allocate, backpressure, and MMIO");
        $finish(0);
    end

    initial #14000 $fatal(1, "DCache test timed out");
endmodule
