// adder2421.sv - 4-digit decimal adder in the 2421 code, on top of a 16-bit binary adder.
//
// 2421 code: digits 0-4 are 0000-0100, digits 5-9 are 1011-1111 (value + 6). It is self-complementing (inverting
// the four bits gives 9 - d), which makes decimal subtraction by complement-and-add easy.
//
// Per digit, the binary sum X of two codes plus a carry lands in the invalid range 0101-1010 exactly when it must
// be corrected:
//   no carry out of the digit: both digits were "low" (0-4) and the sum needs + 6
//   carry out of the digit:    both digits were "high" (codes 11-15) and the sum needs - 6
// and the binary carry out of each digit is exactly the decimal carry (it needs no correction):
//   both low  : X <= 9, no binary carry, no decimal carry
//   one high  : X = (a + b + c) + 6 reaches 16 exactly when a + b + c >= 10
//   both high : X >= 5 + 5 + 12 = 22 always carries, and a + b >= 10 is always a decimal carry
// So a CLA's block carries are the decimal carries too, and the corrector sits after the adder, off the carry path.
// verilator lint_off DECLFILENAME

// add or subtract 6 from a 4-bit value, 2-input gates and inverters only (sub = 1: - 6)
//   z0 = x0    z1 = x1'    r2 = x1 xor sub    z2 = x2' xor r2    z3 = x3 xor ((x2 xor sub) + r2)
module pm6 (
  input  logic [3:0] x,
  input  logic       sub,
  output logic [3:0] z
);
  logic r2, nx2, t, u;
  assign z[0] = x[0];
  g_not  u_z1 (.a(x[1]), .y(z[1]));
  g_xor2 u_r2 (.a(x[1]), .b(sub), .y(r2));
  g_not  u_n2 (.a(x[2]), .y(nx2));
  g_xor2 u_z2 (.a(nx2),  .b(r2),  .y(z[2]));
  g_xor2 u_t  (.a(x[2]), .b(sub), .y(t));
  g_or #(2) u_u (.a({t, r2}), .y(u));
  g_xor2 u_z3 (.a(x[3]), .b(u),   .y(z[3]));
endmodule

// one digit's correction: invalid = X in 0101..1010, then X +- 6 (sub = carry out of the digit)
module digit2421_fix (
  input  logic [3:0] x,
  input  logic       carry,
  output logic [3:0] s
);
  // invalid = x3' x2 x1 + x3' x2 x0 + x3 x2' x1' + x3 x2' x0'
  logic n3, n2, n1, n0, t0, t1, t2, t3, invalid;
  logic [3:0] z;
  g_not u_n3 (.a(x[3]), .y(n3));
  g_not u_n2 (.a(x[2]), .y(n2));
  g_not u_n1 (.a(x[1]), .y(n1));
  g_not u_n0 (.a(x[0]), .y(n0));
  g_and #(3) u_t0 (.a({n3, x[2], x[1]}), .y(t0));
  g_and #(3) u_t1 (.a({n3, x[2], x[0]}), .y(t1));
  g_and #(3) u_t2 (.a({x[3], n2, n1}),   .y(t2));
  g_and #(3) u_t3 (.a({x[3], n2, n0}),   .y(t3));
  g_or  #(4) u_iv (.a({t0, t1, t2, t3}), .y(invalid));
  pm6 u_pm6 (.x, .sub(carry), .z);
  for (genvar i = 0; i < 4; i++) begin : g_sel
    g_mux2 u_m (.s(invalid), .d0(x[i]), .d1(z[i]), .y(s[i]));
  end
endmodule

// 4-digit 2421 adder. ADDER: 0 ripple-carry, 1 single-level CLA, 2 two-level CLA
module adder2421 #(
  parameter int ADDER = 2
) (
  input  logic [15:0] x,        // four 2421 digits, most significant digit in bits 15:12
  input  logic [15:0] y,
  input  logic        cin,
  output logic [15:0] s,
  output logic        cout      // decimal carry out
);
  logic [15:0] bin;
  logic [3:0]  cblk;
  logic        bcout;
  if (ADDER == 0) begin : g_rca
    rca16 u_add (.x, .y, .cin, .s(bin), .cout(bcout), .cblk);
  end else if (ADDER == 1) begin : g_cla1
    cla16_single u_add (.x, .y, .cin, .s(bin), .cout(bcout), .cblk);
  end else begin : g_cla2
    cla16_two_level u_add (.x, .y, .cin, .s(bin), .cout(bcout), .cblk);
  end
  for (genvar d = 0; d < 4; d++) begin : g_digit
    digit2421_fix u_fix (.x(bin[4*d +: 4]), .carry(cblk[d]), .s(s[4*d +: 4]));
  end
  assign cout = bcout;
endmodule
