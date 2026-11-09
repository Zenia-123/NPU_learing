`timescale 1ns/1ps

// Banked SRAM request router and fixed-priority arbiter.
// Verilog-2005 version. Pure combinational logic: no clock and no state.
// The default parameter configuration is the verified assignment target.
module bank_access_router #(
    parameter integer N_REQ         = 4,
    parameter integer N_BANKS       = 4,
    parameter integer BANK_DEPTH    = 16,
    parameter integer DATA_W        = 8,
    parameter integer GLOBAL_ADDR_W = 8,
    // These widths are parameters because the port widths need them.
    parameter integer LOCAL_ADDR_W  = $clog2(BANK_DEPTH),
    parameter integer OWNER_W       = $clog2(N_REQ)
) (
    input  wire [N_REQ-1:0]                    req_valid,
    input  wire [N_REQ-1:0]                    req_we,
    input  wire [N_REQ*GLOBAL_ADDR_W-1:0]      req_addr_flat,
    input  wire [N_REQ*DATA_W-1:0]             req_wdata_flat,

    output reg  [N_REQ-1:0]                    req_grant,
    output reg  [N_REQ-1:0]                    req_stall,
    output reg  [N_REQ-1:0]                    req_error,

    output reg  [N_BANKS-1:0]                  bank_en,
    output reg  [N_BANKS-1:0]                  bank_we,
    output reg  [N_BANKS*LOCAL_ADDR_W-1:0]     bank_addr_flat,
    output reg  [N_BANKS*DATA_W-1:0]           bank_wdata_flat,
    output reg  [N_BANKS*OWNER_W-1:0]          bank_owner_flat,
    output reg  [N_BANKS-1:0]                  bank_conflict
);

    // Elaboration-time constants; they do not become physical registers.
    localparam integer BANK_SEL_W  = $clog2(N_BANKS);
    localparam integer TOTAL_WORDS = N_BANKS * BANK_DEPTH;

    // One unpacked dimension is used as a Verilog memory-style array.
    reg [GLOBAL_ADDR_W-1:0] req_addr       [0:N_REQ-1];
    reg [DATA_W-1:0]        req_wdata      [0:N_REQ-1];
    reg                     addr_ok        [0:N_REQ-1];
    reg [BANK_SEL_W-1:0]    req_bank       [0:N_REQ-1];
    reg [LOCAL_ADDR_W-1:0]  req_local_addr [0:N_REQ-1];

    // Flattened candidate matrix. Bit r*N_BANKS+b means request r
    // is a legal candidate for Bank b.
    reg [N_REQ*N_BANKS-1:0] match;

    // Combinational temporary values reused while describing each Bank.
    reg     winner_found;
    integer candidate_count;
    integer r;
    integer b;

    always @(*) begin
        // Complete defaults make every output deterministic and avoid latches.
        req_grant       = {N_REQ{1'b0}};
        req_stall       = {N_REQ{1'b0}};
        req_error       = {N_REQ{1'b0}};
        bank_en         = {N_BANKS{1'b0}};
        bank_we         = {N_BANKS{1'b0}};
        bank_addr_flat  = {(N_BANKS*LOCAL_ADDR_W){1'b0}};
        bank_wdata_flat = {(N_BANKS*DATA_W){1'b0}};
        bank_owner_flat = {(N_BANKS*OWNER_W){1'b0}};
        bank_conflict   = {N_BANKS{1'b0}};
        match           = {(N_REQ*N_BANKS){1'b0}};
        winner_found    = 1'b0;
        candidate_count = 0;

        for (r = 0; r < N_REQ; r = r + 1) begin
            req_addr[r]       = {GLOBAL_ADDR_W{1'b0}};
            req_wdata[r]      = {DATA_W{1'b0}};
            addr_ok[r]        = 1'b0;
            req_bank[r]       = {BANK_SEL_W{1'b0}};
            req_local_addr[r] = {LOCAL_ADDR_W{1'b0}};
        end

        // Unpack each requester and decode its global word address.
        for (r = 0; r < N_REQ; r = r + 1) begin
            req_addr[r] =
                req_addr_flat[r*GLOBAL_ADDR_W +: GLOBAL_ADDR_W];
            req_wdata[r] =
                req_wdata_flat[r*DATA_W +: DATA_W];

            // Check the full address before using its Bank/local slices.
            addr_ok[r]        = (req_addr[r] < TOTAL_WORDS);
            req_bank[r]       = req_addr[r][BANK_SEL_W-1:0];
            req_local_addr[r] = req_addr[r] >> BANK_SEL_W;
            req_error[r]      = req_valid[r] && !addr_ok[r];
        end

        // Build all request-to-Bank candidate bits.
        for (r = 0; r < N_REQ; r = r + 1) begin
            for (b = 0; b < N_BANKS; b = b + 1) begin
                match[r*N_BANKS+b] =
                    req_valid[r] && addr_ok[r] &&
                    (req_bank[r] == b[BANK_SEL_W-1:0]);
            end
        end

        // Each Bank independently selects the lowest-numbered requester.
        for (b = 0; b < N_BANKS; b = b + 1) begin
            winner_found    = 1'b0;
            candidate_count = 0;

            for (r = 0; r < N_REQ; r = r + 1) begin
                if (match[r*N_BANKS+b]) begin
                    candidate_count = candidate_count + 1;

                    if (!winner_found) begin
                        winner_found = 1'b1;
                        req_grant[r] = 1'b1;
                        bank_en[b]   = 1'b1;
                        bank_we[b]   = req_we[r];
                        bank_addr_flat[b*LOCAL_ADDR_W +: LOCAL_ADDR_W] =
                            req_local_addr[r];
                        bank_owner_flat[b*OWNER_W +: OWNER_W] =
                            r[OWNER_W-1:0];
                        bank_wdata_flat[b*DATA_W +: DATA_W] =
                            req_we[r] ? req_wdata[r] : {DATA_W{1'b0}};
                    end
                end
            end

            bank_conflict[b] = (candidate_count > 1);
        end

        // A legal valid loser retries; an invalid address reports error only.
        for (r = 0; r < N_REQ; r = r + 1) begin
            req_stall[r] = req_valid[r] && addr_ok[r] && !req_grant[r];
        end
    end

endmodule
