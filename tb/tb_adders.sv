// tb_adders.sv - functional testbench (zero-delay gates) for every adder in rtl/.
//
//   binary adders (rca16, cla16_single, cla16_two_level): {cout, s} == x + y + cin, and the block carries equal the
//     carries of the reference sum. cla4: all 512 inputs. 16-bit: corner patterns (all propagate, all generate,
//     all kill, alternating) and 100 000 random additions (1 000 000 with Verilator).
//   2421 adders (ripple, single-level, two-level): every pair of digits in every digit position with carry-in 0/1,
//     every decimal carry chain, and 100 000 random 4-digit additions; the sum must be the valid 2421 encoding of
//     (x + y + cin) mod 10000 and cout the decimal carry.
`timescale 1ns/10ps
`include "tb_common.svh"

module tb_adders;
  // ---------------------------------------------------------------- DUTs
  logic [3:0] x4, y4, s4; logic c4in, c4out, gg4, gp4;
  cla4 u_cla4 (.x(x4), .y(y4), .cin(c4in), .s(s4), .cout(c4out), .gg(gg4), .gp(gp4));

  logic [15:0] x, y; logic cin;
  logic [15:0] s_r, s_1, s_2; logic co_r, co_1, co_2; logic [3:0] cb_r, cb_1, cb_2;
  rca16           u_rca (.x, .y, .cin, .s(s_r), .cout(co_r), .cblk(cb_r));
  cla16_single    u_c1  (.x, .y, .cin, .s(s_1), .cout(co_1), .cblk(cb_1));
  cla16_two_level u_c2  (.x, .y, .cin, .s(s_2), .cout(co_2), .cblk(cb_2));

  logic [15:0] d_r, d_1, d_2; logic dc_r, dc_1, dc_2;
  adder2421 #(.ADDER(0)) u_d0 (.x, .y, .cin, .s(d_r), .cout(dc_r));
  adder2421 #(.ADDER(1)) u_d1 (.x, .y, .cin, .s(d_1), .cout(dc_1));
  adder2421 #(.ADDER(2)) u_d2 (.x, .y, .cin, .s(d_2), .cout(dc_2));

  // ---------------------------------------------------------------- references
  function automatic logic [3:0] enc(input int d); return (d < 5) ? 4'(d) : 4'(d + 6); endfunction
  function automatic logic [15:0] enc4(input int v);
    return {enc((v / 1000) % 10), enc((v / 100) % 10), enc((v / 10) % 10), enc(v % 10)};
  endfunction
  function automatic int dec(input logic [3:0] c); return (c < 5) ? int'(c) : int'(c) - 6; endfunction
  function automatic int dec4(input logic [15:0] c);
    return dec(c[15:12]) * 1000 + dec(c[11:8]) * 100 + dec(c[7:4]) * 10 + dec(c[3:0]);
  endfunction

  int errs; string first;
  task automatic fail(input string m); errs++; if (errs == 1) first = m; endtask
  task automatic check_bin();
    logic [16:0] e; logic [3:0] eb;
    #1;
    e = {1'b0, x} + {1'b0, y} + 17'(cin);
    eb[0] = ({1'b0, x[3:0]} + {1'b0, y[3:0]} + 5'(cin)) >> 4;
    eb[1] = ({1'b0, x[7:0]} + {1'b0, y[7:0]} + 9'(cin)) >> 8;
    eb[2] = ({1'b0, x[11:0]} + {1'b0, y[11:0]} + 13'(cin)) >> 12;
    eb[3] = e[16];
    if ({co_r, s_r} !== e || cb_r !== eb) fail($sformatf("rca16 %h + %h + %0d = %0b_%h (cblk %b), expected %h (%b)", x, y, cin, co_r, s_r, cb_r, e, eb));
    if ({co_1, s_1} !== e || cb_1 !== eb) fail($sformatf("cla16_single %h + %h + %0d = %0b_%h (cblk %b), expected %h (%b)", x, y, cin, co_1, s_1, cb_1, e, eb));
    if ({co_2, s_2} !== e || cb_2 !== eb) fail($sformatf("cla16_two_level %h + %h + %0d = %0b_%h (cblk %b), expected %h (%b)", x, y, cin, co_2, s_2, cb_2, e, eb));
  endtask
  task automatic check_dec(input int a, input int b, input int c);
    int t; logic [15:0] es; logic ec;
    x = enc4(a); y = enc4(b); cin = c[0];
    #1;
    t = a + b + c; es = enc4(t % 10000); ec = (t >= 10000);
    if (d_r !== es || dc_r !== ec) fail($sformatf("2421 ripple %0d + %0d + %0d: %h c%0b, expected %h c%0b", a, b, c, d_r, dc_r, es, ec));
    if (d_1 !== es || dc_1 !== ec) fail($sformatf("2421 single-level %0d + %0d + %0d: %h c%0b, expected %h c%0b", a, b, c, d_1, dc_1, es, ec));
    if (d_2 !== es || dc_2 !== ec) fail($sformatf("2421 two-level %0d + %0d + %0d: %h c%0b, expected %h c%0b", a, b, c, d_2, dc_2, es, ec));
  endtask
  task automatic group(input string name);
    `CHECK("FUNC", name, errs == 0, first)
    errs = 0; first = "";
  endtask

  int nrand;
  initial begin
    errs = 0;
    for (int i = 0; i < 512; i++) begin
      logic [4:0] e;
      {c4in, x4, y4} = 9'(i);
      #1;
      e = {1'b0, x4} + {1'b0, y4} + 5'(c4in);
      if ({c4out, s4} !== e) fail($sformatf("cla4 %h + %h + %0d = %0b_%h", x4, y4, c4in, c4out, s4));
      if (c4out !== (gg4 & (gp4 | c4in))) fail($sformatf("cla4 group signals: c4 != G*(P* + c0) for %h + %h + %0d", x4, y4, c4in));
    end
    group("cla4: all 512 inputs, including c4 = G*(P* + c0)");

    for (int c = 0; c < 2; c++) begin
      cin = c[0];
      x = 16'h0000; y = 16'hFFFF; check_bin();      // every bit propagates
      x = 16'h8888; y = 16'h7777; check_bin();
      x = 16'hFFFF; y = 16'hFFFF; check_bin();      // every bit generates
      x = 16'h0000; y = 16'h0000; check_bin();      // every bit kills
      x = 16'hAAAA; y = 16'h5555; check_bin();
      x = 16'hFFFF; y = 16'h0001; check_bin();
      for (int b = 0; b < 16; b++) begin x = 16'hFFFF ^ (16'h1 << b); y = 16'h1 << b; check_bin(); end
    end
    nrand = 100000;
`ifdef VERILATOR
    nrand = 1000000;
`endif
    tb_rng_state = 32'd404;
    for (int i = 0; i < nrand; i++) begin
      {x, y} = {tb_rand()}; cin = tb_rand() & 1;
      check_bin();
    end
    group($sformatf("16-bit binary adders (ripple, single-, two-level CLA): corner patterns + %0d random", nrand));

    for (int pos = 0; pos < 4; pos++)
      for (int a = 0; a < 10; a++) for (int b = 0; b < 10; b++) for (int c = 0; c < 2; c++) begin
        int w; w = 1; for (int k = 0; k < pos; k++) w *= 10;
        check_dec(a * w, b * w, c);
        check_dec(a * w + 9999 % w, b * w, c);    // lower digits all 9: carry chains into this digit
      end
    group("2421 adders: every digit pair in every position, carry-in 0/1, with and without carry chains");

    for (int i = 0; i < nrand / 10; i++) begin
      int a, b;
      a = int'(tb_rand() % 10000); b = int'(tb_rand() % 10000);
      check_dec(a, b, tb_rand() & 1);
    end
    check_dec(9999, 0, 1); check_dec(9999, 9999, 1); check_dec(0, 0, 0); check_dec(5000, 5000, 0);
    group($sformatf("2421 adders: %0d random 4-digit additions and the extremes", nrand / 10));
    `REPORT
    $finish;
  end
endmodule
