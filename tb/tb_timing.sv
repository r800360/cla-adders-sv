// tb_timing.sv - path delays of the adders under the gate-delay model of rtl/gates.sv (compile with GATE_DELAYS).
//
// Two single-input changes that must travel the whole carry chain are applied to each adder:
//   V1  every bit propagates (x_i != y_i), carry-in 0 -> 1
//   V2  every bit but bit 0 propagates, bit 0 goes from propagate to generate (x0: 0 -> 1, y0 = 1), carry-in 0;
//       this also passes through the slow XNOR of the first PG stage
// For every block carry (c4, c8, c12, c16) and the top sum bit of every block (s3, s7, s11, s15) the settle time is
// the time of its last transition. The CLA figures are checked against the values derived by hand from the delay
// model (README.md); ripple-carry and 2421 figures are checked against their closed forms. Finally 20 000 random
// input changes give the slowest observed settle time of every adder.
`timescale 1ns/1ns
`include "tb_common.svh"

module tb_timing;
  logic [15:0] x = '0, y = '0;
  logic cin = 1'b0;
  logic [15:0] s [6];
  logic [3:0]  cb [3];
  logic        co [6];
  rca16           u_r  (.x, .y, .cin, .s(s[0]), .cout(co[0]), .cblk(cb[0]));
  cla16_single    u_1  (.x, .y, .cin, .s(s[1]), .cout(co[1]), .cblk(cb[1]));
  cla16_two_level u_2  (.x, .y, .cin, .s(s[2]), .cout(co[2]), .cblk(cb[2]));
  adder2421 #(.ADDER(0)) u_d0 (.x, .y, .cin, .s(s[3]), .cout(co[3]));
  adder2421 #(.ADDER(1)) u_d1 (.x, .y, .cin, .s(s[4]), .cout(co[4]));
  adder2421 #(.ADDER(2)) u_d2 (.x, .y, .cin, .s(s[5]), .cout(co[5]));

  // last transition time of each watched net: [adder][0..3 = block carries (binary) / cout, 4..7 = s3, s7, s11, s15]
  time last [6][8];
  for (genvar a = 0; a < 6; a++) begin : g_watch
    for (genvar k = 0; k < 4; k++) begin : g_s
      always @(s[a][4*k+3]) last[a][4+k] = $time;
    end
    if (a < 3) begin : g_c
      for (genvar k = 0; k < 4; k++) begin : g_cb
        always @(cb[a][k]) last[a][k] = $time;
      end
    end else begin : g_co
      always @(co[a]) last[a][3] = $time;
    end
  end

  localparam time SETTLE = 1000;
  time t0;
  int  arr [6][8];     // arrival times of the last measurement (-1 = no transition)
  task automatic measure(input logic [15:0] x0, input logic [15:0] y0, input logic c0,
                         input logic [15:0] x1, input logic [15:0] y1, input logic c1);
    x = x0; y = y0; cin = c0;
    #(SETTLE);
    t0 = $time;
    for (int a = 0; a < 6; a++) for (int k = 0; k < 8; k++) last[a][k] = 0;
    x = x1; y = y1; cin = c1;
    #(SETTLE);
    for (int a = 0; a < 6; a++) for (int k = 0; k < 8; k++) arr[a][k] = (last[a][k] >= t0) ? int'(last[a][k] - t0) : -1;
  endtask

  function automatic string names(input int a);
    case (a)
      0: return "ripple-carry";   1: return "single-level CLA";      2: return "two-level CLA";
      3: return "2421 on ripple"; 4: return "2421 on single-level";  default: return "2421 on two-level";
    endcase
  endfunction
  task automatic show(input string vec, input int a);
    if (a < 3)
      $display("  %-5s %-22s c4 %3d  c8 %3d  c12 %3d  c16 %3d   s3 %3d  s7 %3d  s11 %3d  s15 %3d", vec, names(a),
               arr[a][0], arr[a][1], arr[a][2], arr[a][3], arr[a][4], arr[a][5], arr[a][6], arr[a][7]);
    else
      $display("  %-5s %-22s cout %3d                          s3 %3d  s7 %3d  s11 %3d  s15 %3d", vec, names(a),
               arr[a][3], arr[a][4], arr[a][5], arr[a][6], arr[a][7]);
  endtask
  function automatic bit same(input int a, input int e0, input int e1, input int e2, input int e3, input int e4,
                              input int e5, input int e6, input int e7);
    return arr[a][0] == e0 && arr[a][1] == e1 && arr[a][2] == e2 && arr[a][3] == e3 && arr[a][4] == e4 &&
           arr[a][5] == e5 && arr[a][6] == e6 && arr[a][7] == e7;
  endfunction

  function automatic logic [15:0] rand2421();
    logic [15:0] r;
    for (int d = 0; d < 4; d++) begin
      int v;
      v = int'(tb_rand() % 10);
      r[4*d +: 4] = (v < 5) ? 4'(v) : 4'(v + 6);
    end
    return r;
  endfunction

  int v1 [6][8], v2 [6][8];
  int worst [6];
  initial begin
    $display("settle times in gate steps (NOT 2, AND/OR 5+(n-2), XNOR 7, XOR 9, MUX 3):");
    x = '1; y = '1; cin = 1'b1; #(SETTLE);     // the delayed gates only evaluate on input changes: settle every gate
    // V1: every bit propagates, carry-in 0 -> 1
    measure(16'h8888, 16'h7777, 1'b0, 16'h8888, 16'h7777, 1'b1);
    for (int a = 0; a < 3; a++) begin show("V1", a); for (int k = 0; k < 8; k++) v1[a][k] = arr[a][k]; end
    `CHECK("FUNC", "V1 single-level CLA: c4..c16 = 10 20 30 40, s3..s15 = 21 31 41 51",
           same(1, 10, 20, 30, 40, 21, 31, 41, 51), "different settle times (see table)")
    `CHECK("FUNC", "V1 two-level CLA: c4..c16 = 10 12 14 10, s3..s15 = 21 31 33 35",
           same(2, 10, 12, 14, 10, 21, 31, 33, 35), "different settle times (see table)")
    `CHECK("FUNC", "V1 ripple-carry: 10 steps per bit (c4k = 40k), s(4k+3) = c(4k+3) + XOR = 40k + 39",
           same(0, 40, 80, 120, 160, 39, 79, 119, 159), "different settle times (see table)")
    // V2: bit 0 goes from propagate to generate
    measure(16'h8888, 16'h7777, 1'b0, 16'h8889, 16'h7777, 1'b0);
    for (int a = 0; a < 3; a++) begin show("V2", a); for (int k = 0; k < 8; k++) v2[a][k] = arr[a][k]; end
    `CHECK("FUNC", "V2 single-level CLA: c4..c16 = 24 34 44 54, s3..s15 = 28 45 55 65",
           same(1, 24, 34, 44, 54, 28, 45, 55, 65), "different settle times (see table)")
    `CHECK("FUNC", "V2 two-level CLA: c4..c16 = 24 26 28 31, s3..s15 = 28 45 47 49",
           same(2, 24, 26, 28, 31, 28, 45, 47, 49), "different settle times (see table)")

    // the same two experiments on valid 2421 operands: x and y = ~x are complementary digits (every bit propagates)
    measure(16'h1234, 16'hEDCB, 1'b0, 16'h1234, 16'hEDCB, 1'b1);             // 1234 + 8765 (+ 1): 9999 -> 10000
    for (int a = 3; a < 6; a++) begin show("V1", a); for (int k = 0; k < 8; k++) v1[a][k] = arr[a][k]; end
    measure(16'h1230, 16'hEDCF, 1'b0, 16'h1231, 16'hEDCF, 1'b0);             // 1230 + 8769 -> 1231 + 8769
    for (int a = 3; a < 6; a++) begin show("V2", a); for (int k = 0; k < 8; k++) v2[a][k] = arr[a][k]; end
    begin
      bit ok; ok = 1'b1;
      // the decimal carry out is the binary adder's carry (no correction on the carry path)
      for (int a = 3; a < 6; a++) if (v1[a][3] != v1[a-3][3] || v2[a][3] != v2[a-3][3]) ok = 1'b0;
      `CHECK("FUNC", "2421: the decimal carry out settles exactly when the binary carry out does", ok,
             "the correction stage is on the carry path")
      ok = (v1[5][7] < v1[4][7]) && (v1[4][7] < v1[3][7]) && (v2[5][7] < v2[4][7]) && (v2[4][7] < v2[3][7]);
      `CHECK("FUNC", "2421: top digit settles fastest on the two-level CLA, then single-level, then ripple", ok,
             "ordering violated (see table)")
    end

    // random input changes: slowest settle time of any watched output
    tb_rng_state = 32'd7;
    for (int a = 0; a < 6; a++) worst[a] = 0;
    for (int i = 0; i < 20000; i++) begin
      logic [15:0] xa, ya, xb, yb; logic ca, cbit;
      {xa, ya} = tb_rand(); {xb, yb} = tb_rand(); ca = tb_rand() & 1; cbit = tb_rand() & 1;
      x = xa; y = ya; cin = ca;
      #(SETTLE);
      t0 = $time;
      for (int a = 0; a < 6; a++) for (int k = 0; k < 8; k++) last[a][k] = 0;
      x = xb; y = yb; cin = cbit;
      #(SETTLE);
      for (int a = 0; a < 3; a++) for (int k = 0; k < 8; k++)
        if (last[a][k] >= t0 && int'(last[a][k] - t0) > worst[a]) worst[a] = int'(last[a][k] - t0);
    end
    // the same with valid 2421 operands for the decimal adders
    for (int i = 0; i < 20000; i++) begin
      logic [15:0] xa, ya, xb, yb; logic ca, cbit;
      xa = rand2421(); ya = rand2421(); xb = rand2421(); yb = rand2421(); ca = tb_rand() & 1; cbit = tb_rand() & 1;
      x = xa; y = ya; cin = ca;
      #(SETTLE);
      t0 = $time;
      for (int a = 0; a < 6; a++) for (int k = 0; k < 8; k++) last[a][k] = 0;
      x = xb; y = yb; cin = cbit;
      #(SETTLE);
      for (int a = 3; a < 6; a++) for (int k = 3; k < 8; k++)
        if (last[a][k] >= t0 && int'(last[a][k] - t0) > worst[a]) worst[a] = int'(last[a][k] - t0);
    end
    $display("  slowest settle time over 20 000 random input changes: ripple %0d, single-level %0d, two-level %0d",
             worst[0], worst[1], worst[2]);
    $display("  2421 adders, 20 000 random changes of valid operands: on ripple %0d, on single-level %0d, on two-level %0d",
             worst[3], worst[4], worst[5]);
    `CHECK("FUNC", "random input changes: two-level CLA < single-level CLA < ripple-carry, binary and 2421",
           worst[2] < worst[1] && worst[1] < worst[0] && worst[5] < worst[4] && worst[4] < worst[3],
           "ordering violated")
    `REPORT
    $finish;
  end
endmodule
