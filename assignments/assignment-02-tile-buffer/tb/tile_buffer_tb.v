`timescale 1ns/1ps
`default_nettype none

module tile_buffer_tb;

    localparam integer BANK_DEPTH = 4;
    localparam integer DATA_W     = 8;
    localparam integer ADDR_W     = 2;

    reg                  clk;
    reg                  rst_n;

    reg                  dma_wr_en;
    reg [ADDR_W-1:0]     dma_wr_addr;
    reg [DATA_W-1:0]     dma_wr_data;
    reg                  dma_wr_last;
    reg                  dma_bootstrap;

    reg                  compute_rd_en;
    reg [ADDR_W-1:0]     compute_rd_addr;
    reg                  compute_rd_last;
    wire [DATA_W-1:0]    compute_rd_data;

    reg                  swap_req;

    wire                 compute_tile_valid;
    wire                 tile_done;
    wire                 next_tile_ready;

    integer error_count;

    tile_buffer #(
        .BANK_DEPTH(BANK_DEPTH),
        .DATA_W(DATA_W),
        .ADDR_W(ADDR_W)
    ) dut (
        .clk                (clk),
        .rst_n              (rst_n),
        .dma_wr_en          (dma_wr_en),
        .dma_wr_addr        (dma_wr_addr),
        .dma_wr_data        (dma_wr_data),
        .dma_wr_last        (dma_wr_last),
        .dma_bootstrap      (dma_bootstrap),
        .compute_rd_en      (compute_rd_en),
        .compute_rd_addr    (compute_rd_addr),
        .compute_rd_last    (compute_rd_last),
        .compute_rd_data    (compute_rd_data),
        .swap_req           (swap_req),
        .compute_tile_valid (compute_tile_valid),
        .tile_done          (tile_done),
        .next_tile_ready    (next_tile_ready)
    );

    always #5 clk = ~clk;

    task expect_bit;
        input actual;
        input expected;
        input [8*72-1:0] label;
        begin
            if (actual !== expected) begin
                error_count = error_count + 1;
                $display("FAIL: %0s, expected=%b actual=%b",
                         label, expected, actual);
            end
            else begin
                $display("PASS: %0s", label);
            end
        end
    endtask

    task expect_data;
        input [DATA_W-1:0] actual;
        input [DATA_W-1:0] expected;
        input [8*72-1:0] label;
        begin
            if (actual !== expected) begin
                error_count = error_count + 1;
                $display("FAIL: %0s, expected=0x%0h actual=0x%0h",
                         label, expected, actual);
            end
            else begin
                $display("PASS: %0s", label);
            end
        end
    endtask

    task load_first_tile;
        integer i;
        begin
            for (i = 0; i < BANK_DEPTH; i = i + 1) begin
                @(negedge clk);
                dma_wr_en     = 1'b1;
                dma_wr_addr   = i;
                dma_wr_data   = 8'h10 + i;
                dma_wr_last   = (i == BANK_DEPTH - 1);
                dma_bootstrap = 1'b1;

                @(posedge clk);
                #1;
            end

            @(negedge clk);
            dma_wr_en     = 1'b0;
            dma_wr_last   = 1'b0;
            dma_bootstrap = 1'b0;
        end
    endtask

    task compute_and_prefetch;
        integer i;
        begin
            for (i = 0; i < BANK_DEPTH; i = i + 1) begin
                @(negedge clk);

                dma_wr_en     = 1'b1;
                dma_wr_addr   = i;
                dma_wr_data   = 8'h20 + i;
                dma_wr_last   = (i == BANK_DEPTH - 1);
                dma_bootstrap = 1'b0;

                compute_rd_en   = 1'b1;
                compute_rd_addr = i;
                compute_rd_last = (i == BANK_DEPTH - 1);

                if (i == 0)
                    expect_data(compute_rd_data, 8'h00,
                                "first read has not returned yet");
                else
                    expect_data(compute_rd_data, 8'h10 + i - 1,
                                "registered output holds previous read");

                @(posedge clk);
                #1;

                expect_data(compute_rd_data, 8'h10 + i,
                            "synchronous read returns requested Bank0 data");

                if (i == BANK_DEPTH - 1) begin
                    expect_bit(tile_done, 1'b1,
                               "last compute read sets tile_done");
                    expect_bit(next_tile_ready, 1'b1,
                               "last DMA write sets next_tile_ready");
                end
            end

            @(negedge clk);
            dma_wr_en       = 1'b0;
            dma_wr_last     = 1'b0;
            compute_rd_en   = 1'b0;
            compute_rd_last = 1'b0;
        end
    endtask

    task send_swap_pulse;
        begin
            @(negedge clk);
            swap_req = 1'b1;

            @(posedge clk);
            #1;

            @(negedge clk);
            swap_req = 1'b0;
        end
    endtask

    task read_new_compute_bank;
        begin
            @(negedge clk);
            compute_rd_en   = 1'b1;
            compute_rd_addr = 0;
            compute_rd_last = 1'b0;

            @(posedge clk);
            #1;
            expect_data(compute_rd_data, 8'h20,
                        "after swap, Compute reads Bank1");

            @(negedge clk);
            compute_rd_en   = 1'b0;
            compute_rd_last = 1'b0;
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;

        dma_wr_en = 1'b0;
        dma_wr_addr = {ADDR_W{1'b0}};
        dma_wr_data = {DATA_W{1'b0}};
        dma_wr_last = 1'b0;
        dma_bootstrap = 1'b0;

        compute_rd_en = 1'b0;
        compute_rd_addr = {ADDR_W{1'b0}};
        compute_rd_last = 1'b0;

        swap_req = 1'b0;
        error_count = 0;

        $dumpfile("waves/tile_buffer_tb.vcd");
        $dumpvars(0, tile_buffer_tb);

        #12;
        rst_n = 1'b1;
        #1;

        expect_bit(compute_tile_valid, 1'b0,
                   "reset leaves compute bank invalid");

        load_first_tile;
        expect_bit(compute_tile_valid, 1'b1,
                   "bootstrap fill makes Bank0 valid");
        expect_bit(next_tile_ready, 1'b0,
                   "bootstrap fill is not next-tile prefetch");

        send_swap_pulse;
        expect_bit(dut.active_bank, 1'b0,
                   "early swap does not change active_bank");

        compute_and_prefetch;
        expect_bit(dut.active_bank, 1'b0,
                   "banks do not swap before swap_req");

        send_swap_pulse;
        expect_bit(dut.active_bank, 1'b1,
                   "safe swap changes active_bank");
        expect_bit(tile_done, 1'b0,
                   "safe swap clears tile_done");
        expect_bit(next_tile_ready, 1'b0,
                   "safe swap clears next_tile_ready");

        read_new_compute_bank;

        if (error_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TEST FAILED: %0d error(s)", error_count);

        #20;
        $finish;
    end

endmodule

`default_nettype wire
