`timescale 1ns/1ps

// Seven directed checks for the Verilog-2005 arbitration stage.
// This remains a smoke test; the full assignment regression is T1-T11.
module tb_arbitration_smoke;
    reg  [3:0]  req_valid;
    reg  [3:0]  req_we;
    reg  [31:0] req_addr_flat;
    reg  [31:0] req_wdata_flat;

    wire [3:0]  req_grant;
    wire [3:0]  req_stall;
    wire [3:0]  req_error;
    wire [3:0]  bank_en;
    wire [3:0]  bank_we;
    wire [3:0]  bank_conflict;
    wire [15:0] bank_addr_flat;
    wire [31:0] bank_wdata_flat;
    wire [7:0]  bank_owner_flat;

    reg  [3:0]  exp_grant;
    reg  [3:0]  exp_stall;
    reg  [3:0]  exp_error;
    reg  [3:0]  exp_en;
    reg  [3:0]  exp_we;
    reg  [3:0]  exp_conflict;
    reg  [15:0] exp_addr;
    reg  [31:0] exp_wdata;
    reg  [7:0]  exp_owner;

    integer passed;
    integer failed;

    bank_access_router dut (
        .req_valid(req_valid),
        .req_we(req_we),
        .req_addr_flat(req_addr_flat),
        .req_wdata_flat(req_wdata_flat),
        .req_grant(req_grant),
        .req_stall(req_stall),
        .req_error(req_error),
        .bank_en(bank_en),
        .bank_we(bank_we),
        .bank_addr_flat(bank_addr_flat),
        .bank_wdata_flat(bank_wdata_flat),
        .bank_owner_flat(bank_owner_flat),
        .bank_conflict(bank_conflict)
    );

    // Give every input and expected output a known value before each vector.
    task clear_case;
        begin
            req_valid     = 4'b0000;
            req_we        = 4'b0000;
            req_addr_flat = 32'b0;
            req_wdata_flat = 32'b0;
            exp_grant     = 4'b0000;
            exp_stall     = 4'b0000;
            exp_error     = 4'b0000;
            exp_en        = 4'b0000;
            exp_we        = 4'b0000;
            exp_conflict  = 4'b0000;
            exp_addr      = 16'b0;
            exp_wdata     = 32'b0;
            exp_owner     = 8'b0;
        end
    endtask

    task drive_req;
        input integer request_index;
        input         valid_value;
        input         write_enable;
        input [7:0]   global_address;
        input [7:0]   write_data;
        begin
            req_valid[request_index] = valid_value;
            req_we[request_index] = write_enable;
            req_addr_flat[request_index*8 +: 8] = global_address;
            req_wdata_flat[request_index*8 +: 8] = write_data;
        end
    endtask

    // Expected fields are written explicitly, independent of DUT arbitration.
    task expect_bank;
        input integer bank_index;
        input [1:0]   owner_value;
        input         write_enable;
        input [3:0]   local_address;
        input [7:0]   write_data;
        input         conflict_value;
        begin
            exp_en[bank_index] = 1'b1;
            exp_we[bank_index] = write_enable;
            exp_addr[bank_index*4 +: 4] = local_address;
            exp_wdata[bank_index*8 +: 8] = write_data;
            exp_owner[bank_index*2 +: 2] = owner_value;
            exp_conflict[bank_index] = conflict_value;
        end
    endtask

    task check_case;
        input [8*64-1:0] case_name;
        begin
            // This delay lets combinational outputs settle in simulation.
            #1;
            if ({req_grant, req_stall, req_error, bank_en, bank_we,
                 bank_addr_flat, bank_wdata_flat, bank_owner_flat,
                 bank_conflict} !==
                {exp_grant, exp_stall, exp_error, exp_en, exp_we,
                 exp_addr, exp_wdata, exp_owner, exp_conflict}) begin
                failed = failed + 1;
                $display("FAIL %0s", case_name);
                $display("grant/stall/error actual=%b/%b/%b expected=%b/%b/%b",
                         req_grant, req_stall, req_error,
                         exp_grant, exp_stall, exp_error);
                $display("en/we/addr/wdata/owner/conflict actual=%h/%h/%h/%h/%h/%h",
                         bank_en, bank_we, bank_addr_flat, bank_wdata_flat,
                         bank_owner_flat, bank_conflict);
                $display("expected=%h/%h/%h/%h/%h/%h", exp_en, exp_we,
                         exp_addr, exp_wdata, exp_owner, exp_conflict);
            end
            else begin
                passed = passed + 1;
                $display("PASS %0s", case_name);
            end
        end
    endtask

    initial begin
        passed = 0;
        failed = 0;

        clear_case;
        drive_req(0, 0, 1, 8'd255, 8'hff);
        check_case("S0 inactive out-of-range request");

        clear_case;
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

        clear_case;
        drive_req(0, 1, 0, 8'd1, 8'ha0);
        drive_req(1, 1, 1, 8'd5, 8'ha1);
        drive_req(2, 1, 0, 8'd9, 8'ha2);
        drive_req(3, 1, 1, 8'd13, 8'ha3);
        exp_grant = 4'b0001;
        exp_stall = 4'b1110;
        expect_bank(1, 0, 0, 0, 8'h00, 1);
        check_case("S2 four candidates on Bank1");

        clear_case;
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

        clear_case;
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

        clear_case;
        drive_req(0, 1, 1, 8'd64, 8'hff);
        drive_req(1, 1, 1, 8'd8, 8'h11);
        drive_req(2, 1, 1, 8'd12, 8'h22);
        drive_req(3, 0, 1, 8'd8, 8'h33);
        exp_grant = 4'b0010;
        exp_stall = 4'b0100;
        exp_error = 4'b0001;
        expect_bank(0, 1, 1, 2, 8'h11, 1);
        check_case("S5 invalid req0 cannot win; req1 beats req2");

        clear_case;
        check_case("S6 outputs clear after active traffic");

        if (failed == 0)
            $display("PASS arbitration smoke: %0d/7 vectors", passed);
        else
            $display("FAIL arbitration smoke: %0d passed, %0d failed",
                     passed, failed);

        $finish;
    end

endmodule
