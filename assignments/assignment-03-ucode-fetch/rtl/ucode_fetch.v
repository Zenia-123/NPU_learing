`default_nettype none
`timescale 1ns/1ps

// =============================================================================
// ucode_fetch.v -- Educational reference baseline for microcode instruction fetch
// =============================================================================
//
// This module reads one 128-bit microcode word at a time from a synchronous
// SRAM and offers it to the decode stage through a valid/ready interface.
// A new SRAM request is issued only after Decode has accepted the current
// instruction.  That deliberately simple policy makes the control flow and
// backpressure behavior easy to observe in simulation.
//
// Address convention:
//   base_addr and pc are both expressed in 128-bit instruction words, rather
//   than byte addresses.  The SRAM request address is base_addr + pc.
//
// Completion convention:
//   * program_len == 0 completes without issuing an SRAM request.
//   * An instruction whose low byte is OP_END completes the program and is not
//     forwarded to Decode.
//   * done is a one-cycle pulse after the FSM has entered S_DONE.
// =============================================================================

module ucode_fetch #(
    parameter integer INSTR_W = 128,
    parameter integer ADDR_W  = 4
) (
    // Clock and active-low asynchronous reset.
    input  wire                 clk,
    input  wire                 rst_n,

    // Program-control inputs.  start is expected to be a one-cycle pulse.
    input  wire                 start,
    input  wire                 stop,
    input  wire [ADDR_W-1:0]    base_addr,
    input  wire [ADDR_W-1:0]    program_len,

    // Read-only microcode SRAM interface.  rd_valid may arrive one or more
    // cycles after rd_en; Fetch remains in S_WAIT_DATA until it does.
    output reg                  rd_en,
    output reg  [ADDR_W-1:0]    rd_addr,
    input  wire [INSTR_W-1:0]   rd_data,
    input  wire                 rd_valid,

    // Instruction delivery interface to Decode.
    // A transfer occurs on a rising clock edge when both valid and ready are 1.
    output reg                  instr_valid,
    input  wire                 instr_ready,
    output reg  [INSTR_W-1:0]   instr_data,

    // Observable execution status.  pc is an offset relative to base_addr.
    output wire [ADDR_W-1:0]    pc,
    output wire                 done,
    output wire                 busy
);

    // The test ISA places the opcode in instruction bits [7:0].
    localparam [7:0] OP_END = 8'hff;

    // Six-state controller:
    // IDLE -> FETCH -> WAIT_DATA -> DISPATCH -> INCREMENT -> FETCH ...
    //                                               |
    //                                              DONE -> IDLE
    localparam [2:0]
        S_IDLE      = 3'd0,
        S_FETCH     = 3'd1,
        S_WAIT_DATA = 3'd2,
        S_DISPATCH  = 3'd3,
        S_INCREMENT = 3'd4,
        S_DONE      = 3'd5;

    reg [2:0] state_q;
    reg [2:0] state_d;

    // Registers ending in _q hold the current hardware state.  The matching
    // _d signals are purely combinational next-state values.
    reg [ADDR_W-1:0] pc_q;
    reg [ADDR_W-1:0] pc_d;
    reg [ADDR_W-1:0] base_q;
    reg [ADDR_W-1:0] base_d;
    reg [ADDR_W-1:0] len_q;
    reg [ADDR_W-1:0] len_d;

    // The buffer decouples SRAM-return timing from Decode backpressure.
    reg [INSTR_W-1:0] instr_buf_q;
    reg [INSTR_W-1:0] instr_buf_d;

    // A registered completion pulse lets busy deassert at the same time done
    // is visible externally.
    reg done_q;
    reg done_d;

    wire fetched_is_end;
    wire [ADDR_W-1:0] pc_plus1;

    assign fetched_is_end = (rd_data[7:0] == OP_END);
    assign pc_plus1       = pc_q + 1'b1;

    // -------------------------------------------------------------------------
    // Combinational next-state logic and Moore-style outputs
    // -------------------------------------------------------------------------
    always @(*) begin
        // Default assignments mean "hold the current register value".  They
        // prevent accidental latches when a state does not update a register.
        state_d     = state_q;
        pc_d        = pc_q;
        base_d      = base_q;
        len_d       = len_q;
        instr_buf_d = instr_buf_q;
        done_d      = 1'b0;

        // Default output values while not actively requesting or dispatching.
        rd_en       = 1'b0;
        rd_addr     = {ADDR_W{1'b0}};
        instr_valid = 1'b0;
        instr_data  = instr_buf_q;

        case (state_q)
            // Wait for a new program request and snapshot its configuration.
            S_IDLE: begin
                if (start) begin
                    pc_d   = {ADDR_W{1'b0}};
                    base_d = base_addr;
                    len_d  = program_len;

                    // Zero-length programs have no first instruction to read.
                    if (program_len == {ADDR_W{1'b0}})
                        state_d = S_DONE;
                    else
                        state_d = S_FETCH;
                end
            end

            // Present one read request to the synchronous SRAM for one cycle.
            S_FETCH: begin
                rd_en   = 1'b1;
                rd_addr = base_q + pc_q;
                state_d = S_WAIT_DATA;
            end

            // Do not use rd_data until the SRAM explicitly marks it valid.
            S_WAIT_DATA: begin
                if (stop) begin
                    state_d = S_DONE;
                end
                else if (rd_valid) begin
                    instr_buf_d = rd_data;

                    // OP_END is a fetch-side terminator, not a Decode command.
                    if (fetched_is_end)
                        state_d = S_DONE;
                    else
                        state_d = S_DISPATCH;
                end
            end

            // Hold both valid and data stable until Decode accepts the word.
            S_DISPATCH: begin
                instr_valid = 1'b1;
                instr_data  = instr_buf_q;

                if (stop) begin
                    state_d = S_DONE;
                end
                else if (instr_ready) begin
                    state_d = S_INCREMENT;
                end
            end

            // Advance only after a valid/ready transfer has completed.
            S_INCREMENT: begin
                pc_d = pc_plus1;

                if (stop) begin
                    state_d = S_DONE;
                end
                else if (pc_plus1 >= len_q) begin
                    state_d = S_DONE;
                end
                else begin
                    state_d = S_FETCH;
                end
            end

            // done_d is captured at the next rising edge, producing a one-cycle
            // done_q pulse while the state machine has already returned idle.
            S_DONE: begin
                done_d  = 1'b1;
                state_d = S_IDLE;
            end

            default: begin
                state_d = S_IDLE;
            end
        endcase

        // stop has priority over normal activity.  The state-specific checks
        // above make the intent explicit; this final override covers all active
        // states uniformly.
        if (stop && (state_q != S_IDLE) && (state_q != S_DONE))
            state_d = S_DONE;
    end

    // -------------------------------------------------------------------------
    // Sequential state storage
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q     <= S_IDLE;
            pc_q        <= {ADDR_W{1'b0}};
            base_q      <= {ADDR_W{1'b0}};
            len_q       <= {ADDR_W{1'b0}};
            instr_buf_q <= {INSTR_W{1'b0}};
            done_q      <= 1'b0;
        end
        else begin
            state_q     <= state_d;
            pc_q        <= pc_d;
            base_q      <= base_d;
            len_q       <= len_d;
            instr_buf_q <= instr_buf_d;
            done_q      <= done_d;
        end
    end

    // Continuous status outputs are derived from registered state only.
    assign pc   = pc_q;
    assign done = done_q;
    assign busy = (state_q != S_IDLE);

endmodule

`default_nettype wire
