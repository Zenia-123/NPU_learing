`default_nettype none
`timescale 1ns/1ps

// =============================================================================
// ucode_fetch_tb.v -- Self-checking testbench for the educational baseline
// =============================================================================
// The testbench supplies a behavioral one-cycle-latency SRAM and verifies:
//   1. program-length completion after three normal instructions;
//   2. stable instruction/PC behavior during Decode backpressure, then OP_END;
//   3. stop while Fetch is waiting for SRAM data.
// =============================================================================

module ucode_fetch_tb;

    localparam INSTR_W = 128;
    localparam ADDR_W  = 4;

    reg clk;
    reg rst_n;

    reg start;
    reg stop;
    reg [ADDR_W-1:0] base_addr;
    reg [ADDR_W-1:0] program_len;

    wire rd_en;
    wire [ADDR_W-1:0] rd_addr;
    reg [INSTR_W-1:0] rd_data;
    reg rd_valid;

    wire instr_valid;
    reg  instr_ready;
    wire [INSTR_W-1:0] instr_data;
    wire [ADDR_W-1:0] pc;

    wire done;
    wire busy;

    // Sixteen 128-bit instruction words are sufficient for these directed tests.
    reg [INSTR_W-1:0] mem [0:15];

    integer accepted_count;
    integer errors;

    // These capture the item that must remain unchanged during a stall.
    reg [INSTR_W-1:0] held_instr;
    reg [ADDR_W-1:0] held_pc;

    ucode_fetch #(
        .INSTR_W(INSTR_W),
        .ADDR_W (ADDR_W)
    ) dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .start       (start),
        .stop        (stop),
        .base_addr   (base_addr),
        .program_len (program_len),
        .rd_en       (rd_en),
        .rd_addr     (rd_addr),
        .rd_data     (rd_data),
        .rd_valid    (rd_valid),
        .instr_valid (instr_valid),
        .instr_ready (instr_ready),
        .instr_data  (instr_data),
        .pc          (pc),
        .done        (done),
        .busy        (busy)
    );

    // A 10 ns period gives a convenient waveform scale.
    always #5 clk = ~clk;

    // -------------------------------------------------------------------------
    // Behavioral synchronous SRAM model
    // -------------------------------------------------------------------------
    // Sampling rd_en/address at a rising edge and updating rd_data with a
    // nonblocking assignment models a registered, one-cycle-latency read.
    always @(posedge clk) begin
        if (!rst_n) begin
            rd_valid <= 1'b0;
            rd_data  <= {INSTR_W{1'b0}};
        end
        else begin
            rd_valid <= rd_en;

            if (rd_en)
                rd_data <= mem[rd_addr];
        end
    end

    // Count only real Fetch-to-Decode transfers, not merely valid assertions.
    always @(posedge clk) begin
        if (!rst_n) begin
            accepted_count <= 0;
        end
        else if (instr_valid && instr_ready) begin
            $display("[%0t] Decode receives: pc=%0d opcode=0x%02h",
                     $time, pc, instr_data[7:0]);
            accepted_count <= accepted_count + 1;
        end
    end

    // Hold reset long enough for every sequential block to observe it, then
    // bring Decode into its initially-ready state.
    task reset_dut;
    begin
        start       = 1'b0;
        stop        = 1'b0;
        instr_ready = 1'b0;
        base_addr   = {ADDR_W{1'b0}};
        program_len = {ADDR_W{1'b0}};

        @(negedge clk);
        rst_n = 1'b0;

        repeat (2) @(posedge clk);

        @(negedge clk);
        rst_n       = 1'b1;
        instr_ready = 1'b1;
    end
    endtask

    // Drive start on a falling edge so all configuration signals are stable
    // before the following active clock edge.
    task start_program;
        input [ADDR_W-1:0] task_base;
        input [ADDR_W-1:0] task_len;
    begin
        @(negedge clk);
        base_addr   = task_base;
        program_len = task_len;
        start       = 1'b1;

        @(negedge clk);
        start = 1'b0;
    end
    endtask

    task check_count;
        input integer expected_count;
    begin
        if (accepted_count != expected_count) begin
            $display("ERROR: expected %0d accepted instructions, got %0d",
                     expected_count, accepted_count);
            errors = errors + 1;
        end
    end
    endtask

    initial begin
        clk    = 1'b0;
        rst_n  = 1'b0;
        errors = 0;

        // Test 1 program: three normal instructions, stopped by length.
        mem[0] = {120'd0, 8'h11};
        mem[1] = {120'd0, 8'h22};
        mem[2] = {120'd0, 8'h33};

        // Test 2 program: an OP_END terminates fetching after two transfers.
        mem[4] = {120'd0, 8'h41};
        mem[5] = {120'd0, 8'h42};
        mem[6] = {120'd0, 8'hff};

        // Test 3 program: stop arrives while the first SRAM read is returning.
        mem[8]  = {120'd0, 8'h51};
        mem[9]  = {120'd0, 8'h52};
        mem[10] = {120'd0, 8'h53};

        $dumpfile("waves/ucode_fetch_tb.vcd");
        $dumpvars(0, ucode_fetch_tb);

        // ---------------------------------------------------------------------
        // Test 1: normal sequential fetch, with program_len as the terminator.
        // ---------------------------------------------------------------------
        reset_dut;
        start_program(4'd0, 4'd3);

        wait (done == 1'b1);
        check_count(3);

        // ---------------------------------------------------------------------
        // Test 2: hold Decode not-ready for two full cycles while opcode 0x42
        // is presented.  Fetch must keep valid, data, and PC unchanged.
        // ---------------------------------------------------------------------
        reset_dut;
        start_program(4'd4, 4'd8);

        wait (instr_valid && (instr_data[7:0] == 8'h42));

        @(negedge clk);
        instr_ready = 1'b0;
        held_instr  = instr_data;
        held_pc     = pc;

        repeat (2) begin
            @(posedge clk);
            #1;

            if (instr_valid !== 1'b1) begin
                $display("ERROR: instr_valid fell during backpressure");
                errors = errors + 1;
            end

            if (instr_data !== held_instr) begin
                $display("ERROR: instr_data changed during backpressure");
                errors = errors + 1;
            end

            if (pc !== held_pc) begin
                $display("ERROR: pc changed during backpressure");
                errors = errors + 1;
            end
        end

        @(negedge clk);
        instr_ready = 1'b1;

        wait (done == 1'b1);
        check_count(2);

        // ---------------------------------------------------------------------
        // Test 3: stopping in S_WAIT_DATA must prevent Decode from receiving
        // the first fetched word.
        // ---------------------------------------------------------------------
        reset_dut;
        start_program(4'd8, 4'd3);

        wait (rd_valid == 1'b1);

        @(negedge clk);
        stop = 1'b1;

        @(negedge clk);
        stop = 1'b0;

        wait (done == 1'b1);
        check_count(0);

        if (errors == 0)
            $display("PASS: all ucode_fetch tests passed.");
        else
            $display("FAIL: %0d error(s) found.", errors);

        #20;
        $finish;
    end

    // A watchdog converts a broken FSM into a finite, diagnosable simulation.
    initial begin
        #20000;
        $display("FAIL: simulation timeout.");
        $finish;
    end

endmodule

`default_nettype wire
