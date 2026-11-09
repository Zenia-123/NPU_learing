// Stage 1: interface, combinational defaults, unpacking and address decoding.
// INCOMPLETE: no request-to-Bank matching, arbitration or successful routing yet.
// Supported for this lesson: the default configuration below.
// Future parameter changes require a separate width/range review.
module bank_access_router #(
    parameter int N_REQ         = 4,
    parameter int N_BANKS       = 4,
    parameter int BANK_DEPTH    = 16,
    parameter int DATA_W        = 8,
    parameter int GLOBAL_ADDR_W = 8,
    // Port widths must be known before declaring the ports.
    localparam int LOCAL_ADDR_W = $clog2(BANK_DEPTH),
    localparam int OWNER_W      = $clog2(N_REQ)
) (
    input  logic [N_REQ-1:0]                   req_valid,
    input  logic [N_REQ-1:0]                   req_we,
    input  logic [N_REQ*GLOBAL_ADDR_W-1:0]     req_addr_flat,
    input  logic [N_REQ*DATA_W-1:0]            req_wdata_flat,

    output logic [N_REQ-1:0]                   req_grant,
    output logic [N_REQ-1:0]                   req_stall,
    output logic [N_REQ-1:0]                   req_error,

    output logic [N_BANKS-1:0]                 bank_en,
    output logic [N_BANKS-1:0]                 bank_we,
    output logic [N_BANKS*LOCAL_ADDR_W-1:0]    bank_addr_flat,
    output logic [N_BANKS*DATA_W-1:0]          bank_wdata_flat,
    output logic [N_BANKS*OWNER_W-1:0]         bank_owner_flat,
    output logic [N_BANKS-1:0]                 bank_conflict
);

    // Constants are elaboration-time values, not physical registers.
    localparam int BANK_SEL_W  = $clog2(N_BANKS);
    localparam int TOTAL_WORDS = N_BANKS * BANK_DEPTH;

    // Unpacked arrays name the wires belonging to each requester.
    logic [GLOBAL_ADDR_W-1:0] req_addr       [0:N_REQ-1];
    logic [DATA_W-1:0]        req_wdata      [0:N_REQ-1];
    logic                    addr_ok        [0:N_REQ-1];
    logic [BANK_SEL_W-1:0]    req_bank       [0:N_REQ-1];
    logic [LOCAL_ADDR_W-1:0]  req_local_addr [0:N_REQ-1];

    // Reserved for the arbitration lesson; held at zero in this stage.
    logic match [0:N_REQ-1][0:N_BANKS-1];
    logic winner_found;
    integer candidate_count;

    always_comb begin
        // Every output receives a value on every path.
        req_grant       = '0;
        req_stall       = '0;
        req_error       = '0;
        bank_en         = '0;
        bank_we         = '0;
        bank_addr_flat  = '0;
        bank_wdata_flat = '0;
        bank_owner_flat = '0;
        bank_conflict   = '0;
        winner_found    = 1'b0;
        candidate_count = 0;

        // Constant-bound loops describe parallel combinational structures.
        for (int r = 0; r < N_REQ; r = r + 1) begin
            req_addr[r]       = '0;
            req_wdata[r]      = '0;
            addr_ok[r]        = 1'b0;
            req_bank[r]       = '0;
            req_local_addr[r] = '0;
            for (int b = 0; b < N_BANKS; b = b + 1) begin
                match[r][b] = 1'b0;
            end
        end

        for (int r = 0; r < N_REQ; r = r + 1) begin
            // Request 0 occupies the least-significant slice.
            req_addr[r] =
                req_addr_flat[r*GLOBAL_ADDR_W +: GLOBAL_ADDR_W];
            req_wdata[r] =
                req_wdata_flat[r*DATA_W +: DATA_W];

            // Compare the FULL global word address before trusting slices.
            addr_ok[r] = (req_addr[r] < TOTAL_WORDS);
            req_bank[r] = req_addr[r][BANK_SEL_W-1:0];
            req_local_addr[r] = req_addr[r] >> BANK_SEL_W;

            // Invalid requesters must not raise address errors.
            req_error[r] = req_valid[r] && !addr_ok[r];
        end

        // TODO next stage: match = valid && addr_ok && Bank equality.
        // TODO next stage: per-Bank priority, output muxes, grant/stall/conflict.
        // Current grant/stall and Bank outputs intentionally remain zero.
    end
endmodule
