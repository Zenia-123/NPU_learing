`timescale 1ns/1ps

// Seven directed combinational checks for the arbitration stage.
// This is not the full T1-T11 regression or a waveform testbench.
module tb_arbitration_smoke;
    logic [3:0] req_valid, req_we;
    logic [31:0] req_addr_flat, req_wdata_flat;
    wire [3:0] req_grant, req_stall, req_error;
    wire [3:0] bank_en, bank_we, bank_conflict;
    wire [15:0] bank_addr_flat;
    wire [31:0] bank_wdata_flat;
    wire [7:0] bank_owner_flat;

    logic [3:0] exp_grant, exp_stall, exp_error;
    logic [3:0] exp_en, exp_we, exp_conflict;
    logic [15:0] exp_addr;
    logic [31:0] exp_wdata;
    logic [7:0] exp_owner;
    integer passed = 0;

    bank_access_router dut (
        .req_valid(req_valid), .req_we(req_we),
        .req_addr_flat(req_addr_flat), .req_wdata_flat(req_wdata_flat),
        .req_grant(req_grant), .req_stall(req_stall), .req_error(req_error),
        .bank_en(bank_en), .bank_we(bank_we),
        .bank_addr_flat(bank_addr_flat), .bank_wdata_flat(bank_wdata_flat),
        .bank_owner_flat(bank_owner_flat), .bank_conflict(bank_conflict)
    );

    // Start each vector with known inputs and fully specified expectations.
    task automatic clear_case;
        begin
            req_valid = '0;
            req_we = '0;
            req_addr_flat = '0;
            req_wdata_flat = '0;
            exp_grant = '0;
            exp_stall = '0;
            exp_error = '0;
            exp_en = '0;
            exp_we = '0;
            exp_conflict = '0;
            exp_addr = '0;
            exp_wdata = '0;
            exp_owner = '0;
        end
    endtask

    task automatic drive_req(input integer r, input logic valid,
                             input logic we, input logic [7:0] addr,
                             input logic [7:0] data);
        begin
            req_valid[r] = valid;
            req_we[r] = we;
            req_addr_flat[r*8 +: 8] = addr;
            req_wdata_flat[r*8 +: 8] = data;
        end
    endtask

    // Expected Bank fields are written explicitly, not selected by a second
    // copy of the DUT's matching and priority algorithm.
    task automatic expect_bank(input integer b, input logic [1:0] owner,
                               input logic we, input logic [3:0] addr,
                               input logic [7:0] data, input logic conflict);
        begin
            exp_en[b] = 1'b1;
            exp_we[b] = we;
            exp_addr[b*4 +: 4] = addr;
            exp_wdata[b*8 +: 8] = data;
            exp_owner[b*2 +: 2] = owner;
            exp_conflict[b] = conflict;
        end
    endtask

    task automatic check_case(input string name);
        begin
            // Simulation settling delay only; not a measured hardware delay.
            #1;
            if ({req_grant, req_stall, req_error, bank_en, bank_we,
                 bank_addr_flat, bank_wdata_flat, bank_owner_flat,
                 bank_conflict} !==
                {exp_grant, exp_stall, exp_error, exp_en, exp_we,
                 exp_addr, exp_wdata, exp_owner, exp_conflict}) begin
                $display("FAIL %s", name);
                $display("grant/stall/error actual=%b/%b/%b expected=%b/%b/%b",
                         req_grant, req_stall, req_error,
                         exp_grant, exp_stall, exp_error);
                $display("en/we/addr/wdata/owner/conflict actual=%h/%h/%h/%h/%h/%h",
                         bank_en, bank_we, bank_addr_flat, bank_wdata_flat,
                         bank_owner_flat, bank_conflict);
                $display("expected=%h/%h/%h/%h/%h/%h", exp_en, exp_we,
                         exp_addr, exp_wdata, exp_owner, exp_conflict);
                $fatal(1, "arbitration smoke mismatch");
            end
            passed = passed + 1;
            $display("PASS %s", name);
        end
    endtask

    initial begin
        clear_case();
        drive_req(0, 0, 1, 8'd255, 8'hff);
        check_case("S0 inactive out-of-range request");

        clear_case();
        drive_req(0, 1, 0, 8'd0, 8'hf0);
        drive_req(1, 1, 1, 8'd5, 8'ha1);
        drive_req(2, 1, 0, 8'd10, 8'hf2);
        drive_req(3, 1, 1, 8'd15, 8'hb3);
        exp_grant = 4'b1111;
        expect_bank(0, 0, 0, 0, 8'h00, 0);
        expect_bank(1, 1, 1, 1, 8'ha1, 0);
        expect_bank(2, 2, 0, 2, 8'h00, 0);
        expect_bank(3, 3, 1, 3, 8'hb3, 0);
        check_case("S1 four independent Banks");

        clear_case();
        drive_req(0, 1, 0, 8'd1, 8'ha0);
        drive_req(1, 1, 1, 8'd5, 8'ha1);
        drive_req(2, 1, 0, 8'd9, 8'ha2);
        drive_req(3, 1, 1, 8'd13, 8'ha3);
        exp_grant = 4'b0001;
        exp_stall = 4'b1110;
        expect_bank(1, 0, 0, 0, 8'h00, 1);
        check_case("S2 four candidates on Bank1");

        clear_case();
        drive_req(0, 1, 0, 8'd5, 8'hf0);
        drive_req(1, 1, 1, 8'd9, 8'ha1);
        drive_req(2, 1, 1, 8'd14, 8'hb2);
        drive_req(3, 1, 0, 8'd16, 8'hf3);
        exp_grant = 4'b1101;
        exp_stall = 4'b0010;
        expect_bank(0, 3, 0, 4, 8'h00, 0);
        expect_bank(1, 0, 0, 1, 8'h00, 1);
        expect_bank(2, 2, 1, 3, 8'hb2, 0);
        check_case("S3 partial conflict and parallel routing");

        clear_case();
        drive_req(0, 1, 1, 8'd64, 8'hff);
        drive_req(1, 1, 1, 8'd63, 8'hb1);
        drive_req(2, 1, 0, 8'd14, 8'hf2);
        drive_req(3, 1, 1, 8'd16, 8'hd3);
        exp_grant = 4'b1110;
        exp_error = 4'b0001;
        expect_bank(0, 3, 1, 4, 8'hd3, 0);
        expect_bank(2, 2, 0, 3, 8'h00, 0);
        expect_bank(3, 1, 1, 15, 8'hb1, 0);
        check_case("S4 address 63 accepted and 64 rejected");

        clear_case();
        drive_req(0, 1, 1, 8'd64, 8'hff);
        drive_req(1, 1, 1, 8'd8, 8'h11);
        drive_req(2, 1, 1, 8'd12, 8'h22);
        drive_req(3, 0, 1, 8'd8, 8'h33);
        exp_grant = 4'b0010;
        exp_stall = 4'b0100;
        exp_error = 4'b0001;
        expect_bank(0, 1, 1, 2, 8'h11, 1);
        check_case("S5 invalid req0 cannot win; req1 beats req2");

        clear_case();
        check_case("S6 outputs clear after active traffic");
        $display("PASS arbitration smoke: %0d/7 vectors", passed);
        $finish;
    end
endmodule
