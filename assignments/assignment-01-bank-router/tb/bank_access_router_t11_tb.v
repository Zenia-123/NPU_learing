`timescale 1ns/1ps

// Formal directed regression for assignment question 1.
// Covers specification items T1 through T11 and writes a VCD waveform.
module bank_access_router_t11_tb;
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

    integer current_test;
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

    task clear_case;
        begin
            req_valid      = 4'b0000;
            req_we         = 4'b0000;
            req_addr_flat  = 32'b0;
            req_wdata_flat = 32'b0;
            exp_grant      = 4'b0000;
            exp_stall      = 4'b0000;
            exp_error      = 4'b0000;
            exp_en         = 4'b0000;
            exp_we         = 4'b0000;
            exp_conflict   = 4'b0000;
            exp_addr       = 16'b0;
            exp_wdata      = 32'b0;
            exp_owner      = 8'b0;
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

    // Write expected Bank fields explicitly instead of copying DUT logic.
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
        input integer test_number;
        input [8*64-1:0] case_name;
        begin
            current_test = test_number;
            // Testbench settling time only; this is not a hardware cycle.
            #1;
            if ({req_grant, req_stall, req_error, bank_en, bank_we,
                 bank_addr_flat, bank_wdata_flat, bank_owner_flat,
                 bank_conflict} !==
                {exp_grant, exp_stall, exp_error, exp_en, exp_we,
                 exp_addr, exp_wdata, exp_owner, exp_conflict}) begin
                failed = failed + 1;
                $display("FAIL T%0d %0s", test_number, case_name);
                $display("  request actual grant/stall/error=%b/%b/%b",
                         req_grant, req_stall, req_error);
                $display("  request expect grant/stall/error=%b/%b/%b",
                         exp_grant, exp_stall, exp_error);
                $display("  bank actual en/we/addr/data/owner/conflict=%h/%h/%h/%h/%h/%h",
                         bank_en, bank_we, bank_addr_flat, bank_wdata_flat,
                         bank_owner_flat, bank_conflict);
                $display("  bank expect en/we/addr/data/owner/conflict=%h/%h/%h/%h/%h/%h",
                         exp_en, exp_we, exp_addr, exp_wdata,
                         exp_owner, exp_conflict);
            end
            else begin
                passed = passed + 1;
                $display("PASS T%0d %0s", test_number, case_name);
            end
        end
    endtask

    initial begin
        passed = 0;
        failed = 0;
        current_test = 0;
        clear_case;

        $dumpfile("assignments/assignment-01-bank-router/waves/bank_router_t11.vcd");
        $dumpvars(0, current_test, req_valid, req_we,
                     req_addr_flat, req_wdata_flat,
                     req_grant, req_stall, req_error,
                     bank_en, bank_we, bank_addr_flat,
                     bank_wdata_flat, bank_owner_flat, bank_conflict);

        // T1: all requesters inactive.
        clear_case;
        check_case(1, "all requests invalid");

        // T2: one legal read, req2 -> Bank2/local5.
        clear_case;
        drive_req(2, 1, 0, 8'd22, 8'hee);
        exp_grant = 4'b0100;
        expect_bank(2, 2, 0, 5, 8'h00, 0);
        check_case(2, "single legal read");

        // T3: one legal write, req3 -> Bank0/local7.
        clear_case;
        drive_req(3, 1, 1, 8'd28, 8'ha5);
        exp_grant = 4'b1000;
        expect_bank(0, 3, 1, 7, 8'ha5, 0);
        check_case(3, "single legal write");

        // T4: four independent Banks can accept four requests in parallel.
        clear_case;
        drive_req(0, 1, 0, 8'd4,  8'hf0);
        drive_req(1, 1, 1, 8'd9,  8'hd1);
        drive_req(2, 1, 0, 8'd14, 8'hf2);
        drive_req(3, 1, 1, 8'd19, 8'hd3);
        exp_grant = 4'b1111;
        expect_bank(0, 0, 0, 1, 8'h00, 0);
        expect_bank(1, 1, 1, 2, 8'hd1, 0);
        expect_bank(2, 2, 0, 3, 8'h00, 0);
        expect_bank(3, 3, 1, 4, 8'hd3, 0);
        check_case(4, "four requests on different Banks");

        // T5: req1 wins over req3 when both target Bank2.
        clear_case;
        drive_req(1, 1, 1, 8'd6,  8'hb1);
        drive_req(3, 1, 0, 8'd18, 8'hf3);
        exp_grant = 4'b0010;
        exp_stall = 4'b1000;
        expect_bank(2, 1, 1, 1, 8'hb1, 1);
        check_case(5, "two requests on one Bank");

        // T6: all requesters target Bank1; req0 is the only winner.
        clear_case;
        drive_req(0, 1, 0, 8'd1,  8'ha0);
        drive_req(1, 1, 1, 8'd5,  8'ha1);
        drive_req(2, 1, 0, 8'd9,  8'ha2);
        drive_req(3, 1, 1, 8'd13, 8'ha3);
        exp_grant = 4'b0001;
        exp_stall = 4'b1110;
        expect_bank(1, 0, 0, 0, 8'h00, 1);
        check_case(6, "four requests on one Bank");

        // T7: highest legal address maps to Bank3/local15.
        clear_case;
        drive_req(2, 1, 0, 8'd63, 8'hff);
        exp_grant = 4'b0100;
        expect_bank(3, 2, 0, 15, 8'h00, 0);
        check_case(7, "address 63 boundary");

        // T8: address 64 is out of range and must not enable a Bank.
        clear_case;
        drive_req(1, 1, 1, 8'd64, 8'h88);
        exp_error = 4'b0010;
        check_case(8, "address 64 out of range");

        // T9: an inactive requester never raises an address error.
        clear_case;
        drive_req(3, 0, 1, 8'd255, 8'h99);
        check_case(9, "inactive out-of-range address");

        // T10: invalid req0 cannot block legal arbitration or another Bank.
        clear_case;
        drive_req(0, 1, 1, 8'd64, 8'hff);
        drive_req(1, 1, 1, 8'd8,  8'h11);
        drive_req(2, 1, 1, 8'd12, 8'h22);
        drive_req(3, 1, 0, 8'd19, 8'hf3);
        exp_grant = 4'b1010;
        exp_stall = 4'b0100;
        exp_error = 4'b0001;
        expect_bank(0, 1, 1, 2, 8'h11, 1);
        expect_bank(3, 3, 0, 4, 8'h00, 0);
        check_case(10, "one invalid plus three legal requests");

        // T11: first create active traffic, then remove it without reset.
        // A combinational DUT must immediately return all outputs to zero.
        current_test = 11;
        clear_case;
        drive_req(0, 1, 1, 8'd0,  8'h10);
        drive_req(1, 1, 1, 8'd4,  8'h11);
        drive_req(2, 1, 1, 8'd8,  8'h12);
        drive_req(3, 1, 1, 8'd12, 8'h13);
        #1;
        clear_case;
        check_case(11, "outputs clear after changing inputs");

        if ((passed == 11) && (failed == 0))
            $display("RESULT PASS T1-T11: %0d/11 tests", passed);
        else
            $display("RESULT FAIL T1-T11: %0d passed, %0d failed",
                     passed, failed);

        $finish;
    end

endmodule
