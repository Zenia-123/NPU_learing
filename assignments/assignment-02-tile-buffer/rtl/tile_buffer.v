`default_nettype none

module tile_buffer #(
    parameter integer BANK_DEPTH = 16,
    parameter integer DATA_W     = 8,
    parameter integer ADDR_W     =
        (BANK_DEPTH <= 1) ? 1 : $clog2(BANK_DEPTH)
)(
    input  wire                  clk,
    input  wire                  rst_n,

    input  wire                  dma_wr_en,
    input  wire [ADDR_W-1:0]     dma_wr_addr,
    input  wire [DATA_W-1:0]     dma_wr_data,
    input  wire                  dma_wr_last,
    input  wire                  dma_bootstrap,

    input  wire                  compute_rd_en,
    input  wire [ADDR_W-1:0]     compute_rd_addr,
    input  wire                  compute_rd_last,
    output reg  [DATA_W-1:0]     compute_rd_data,

    input  wire                  swap_req,

    output reg                   compute_tile_valid,
    output reg                   tile_done,
    output reg                   next_tile_ready
);

    reg [DATA_W-1:0] bank0 [0:BANK_DEPTH-1];
    reg [DATA_W-1:0] bank1 [0:BANK_DEPTH-1];

    // 0: compute 读 bank0、DMA 正常写 bank1。
    // 1: compute 读 bank1、DMA 正常写 bank0。
    reg active_bank;

    wire swap_fire;
    assign swap_fire = swap_req && tile_done && next_tile_ready;

    // DMA 写路径。启动时填充当前 compute Bank；稳态时填充对侧 Bank。
    always @(posedge clk) begin
        if (dma_wr_en && !swap_fire) begin
            if (dma_bootstrap) begin
                if (active_bank == 1'b0)
                    bank0[dma_wr_addr] <= dma_wr_data;
                else
                    bank1[dma_wr_addr] <= dma_wr_data;
            end
            else begin
                if (active_bank == 1'b0)
                    bank1[dma_wr_addr] <= dma_wr_data;
                else
                    bank0[dma_wr_addr] <= dma_wr_data;
            end
        end
    end

    // Compute 同步读：地址在时钟沿采样，数据在沿后更新到输出寄存器。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            compute_rd_data <= {DATA_W{1'b0}};
        end
        else if (compute_rd_en && compute_tile_valid && !swap_fire) begin
            if (active_bank == 1'b0)
                compute_rd_data <= bank0[compute_rd_addr];
            else
                compute_rd_data <= bank1[compute_rd_addr];
        end
    end

    // 角色、有效性和完成状态。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active_bank        <= 1'b0;
            compute_tile_valid <= 1'b0;
            tile_done          <= 1'b0;
            next_tile_ready    <= 1'b0;
        end
        else if (swap_fire) begin
            active_bank        <= ~active_bank;
            compute_tile_valid <= 1'b1;
            tile_done          <= 1'b0;
            next_tile_ready    <= 1'b0;
        end
        else begin
            if (dma_wr_en && dma_wr_last) begin
                if (dma_bootstrap)
                    compute_tile_valid <= 1'b1;
                else
                    next_tile_ready <= 1'b1;
            end

            if (compute_rd_en &&
                compute_tile_valid &&
                compute_rd_last) begin
                tile_done <= 1'b1;
            end
        end
    end

endmodule

`default_nettype wire
