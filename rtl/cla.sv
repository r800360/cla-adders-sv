// cla.sv - carry-lookahead adders in the dual ("alternative") form, built from rtl/gates.sv.
//
// The textbook CLA uses g = xy, p = x xor y, c+ = g + p c. Swapping AND/OR and XOR/XNOR gives an equivalent form:
//     g*_i = x_i + y_i     p*_i = x_i xnor y_i     c_(i+1) = g*_i (p*_i + c_i)     s_i = p*_i xnor c_i
// (x != y: g* = 1, p* = 0, carry propagates; x = y = 1: generate; x = y = 0: g* = 0, kill.)
// Unrolled, every carry is a product of sums - two gate levels, at most 4 inputs per gate:
//     c1 = g0 (p0 + c0)
//     c2 = g1 (p1 + g0)(p1 + p0 + c0)
//     c3 = g2 (p2 + g1)(p2 + p1 + g0)(p2 + p1 + p0 + c0)
//     G* = g3 (p3 + g2)(p3 + p2 + g1)(p3 + p2 + p1 + g0)       P* = p3 + p2 + p1 + p0       c4 = G* (P* + c0)
// verilator lint_off DECLFILENAME

// 4-bit lookahead unit: carries c1..c4 and the group signals from g*, p* and c0
module cla_lookahead (
  input  logic [3:0] g,       // g*
  input  logic [3:0] p,       // p*
  input  logic       c0,
  output logic [3:0] c,       // carries into bits 0..3: {c3, c2, c1, c0}
  output logic       c4,
  output logic       gg,      // group generate G*
  output logic       gp       // group propagate P*
);
  logic o1, o2a, o2b, o3a, o3b, o3c, o4a, o4b, o4c, o5;
  assign c[0] = c0;
  // c1
  g_or  #(2) u_o1  (.a({p[0], c0}),              .y(o1));
  g_and #(2) u_c1  (.a({g[0], o1}),              .y(c[1]));
  // c2
  g_or  #(2) u_o2a (.a({p[1], g[0]}),            .y(o2a));
  g_or  #(3) u_o2b (.a({p[1], p[0], c0}),        .y(o2b));
  g_and #(3) u_c2  (.a({g[1], o2a, o2b}),        .y(c[2]));
  // c3
  g_or  #(2) u_o3a (.a({p[2], g[1]}),            .y(o3a));
  g_or  #(3) u_o3b (.a({p[2], p[1], g[0]}),      .y(o3b));
  g_or  #(4) u_o3c (.a({p[2], p[1], p[0], c0}),  .y(o3c));
  g_and #(4) u_c3  (.a({g[2], o3a, o3b, o3c}),   .y(c[3]));
  // group generate / propagate and c4
  g_or  #(2) u_o4a (.a({p[3], g[2]}),            .y(o4a));
  g_or  #(3) u_o4b (.a({p[3], p[2], g[1]}),      .y(o4b));
  g_or  #(4) u_o4c (.a({p[3], p[2], p[1], g[0]}), .y(o4c));
  g_and #(4) u_gg  (.a({g[3], o4a, o4b, o4c}),   .y(gg));
  g_or  #(4) u_gp  (.a(p),                       .y(gp));
  g_or  #(2) u_o5  (.a({gp, c0}),                .y(o5));
  g_and #(2) u_c4  (.a({gg, o5}),                .y(c4));
endmodule

// 4-bit adder: PG generation, lookahead, sums
module cla4 (
  input  logic [3:0] x,
  input  logic [3:0] y,
  input  logic       cin,
  output logic [3:0] s,
  output logic       cout,
  output logic       gg,
  output logic       gp
);
  logic [3:0] g, p, c;
  for (genvar i = 0; i < 4; i++) begin : g_bit
    g_or #(2) u_g (.a({x[i], y[i]}), .y(g[i]));
    g_xnor2   u_p (.a(x[i]), .b(y[i]), .y(p[i]));
    g_xnor2   u_s (.a(p[i]), .b(c[i]), .y(s[i]));
  end
  cla_lookahead u_la (.g, .p, .c0(cin), .c, .c4(cout), .gg, .gp);
endmodule

// 16-bit single-level CLA: four 4-bit lookahead blocks, the block carries ripple from block to block
module cla16_single (
  input  logic [15:0] x,
  input  logic [15:0] y,
  input  logic        cin,
  output logic [15:0] s,
  output logic        cout,
  output logic [3:0]  cblk      // carries out of each block: {c16, c12, c8, c4}
);
  logic [4:0] c;
  assign c[0] = cin;
  for (genvar b = 0; b < 4; b++) begin : g_blk
    logic gg_unused, gp_unused;
    cla4 u_blk (.x(x[4*b +: 4]), .y(y[4*b +: 4]), .cin(c[b]), .s(s[4*b +: 4]), .cout(c[b+1]),
                .gg(gg_unused), .gp(gp_unused));
  end
  assign cblk = c[4:1];
  assign cout = c[4];
endmodule

// 16-bit two-level CLA: the blocks' G* / P* feed a second lookahead unit that computes c4, c8, c12, c16 at once
module cla16_two_level (
  input  logic [15:0] x,
  input  logic [15:0] y,
  input  logic        cin,
  output logic [15:0] s,
  output logic        cout,
  output logic [3:0]  cblk
);
  logic [3:0] gg, gp, c;
  logic       c16, ggg_unused, ggp_unused;
  for (genvar b = 0; b < 4; b++) begin : g_blk
    logic cout_unused;
    cla4 u_blk (.x(x[4*b +: 4]), .y(y[4*b +: 4]), .cin(c[b]), .s(s[4*b +: 4]), .cout(cout_unused),
                .gg(gg[b]), .gp(gp[b]));
  end
  cla_lookahead u_la2 (.g(gg), .p(gp), .c0(cin), .c, .c4(c16), .gg(ggg_unused), .gp(ggp_unused));
  assign cblk = {c16, c[3:1]};
  assign cout = c16;
endmodule

// 16-bit ripple-carry adder from textbook full adders (s = x xor y xor c, c+ = xy + (x xor y) c), for comparison
module rca16 (
  input  logic [15:0] x,
  input  logic [15:0] y,
  input  logic        cin,
  output logic [15:0] s,
  output logic        cout,
  output logic [3:0]  cblk
);
  logic [16:0] c;
  assign c[0] = cin;
  for (genvar i = 0; i < 16; i++) begin : g_fa
    logic h, gen, prop;
    g_xor2    u_h  (.a(x[i]), .b(y[i]), .y(h));
    g_xor2    u_s  (.a(h),    .b(c[i]), .y(s[i]));
    g_and #(2) u_g (.a({x[i], y[i]}), .y(gen));
    g_and #(2) u_p (.a({h, c[i]}),    .y(prop));
    g_or  #(2) u_c (.a({gen, prop}),  .y(c[i+1]));
  end
  assign cblk = {c[16], c[12], c[8], c[4]};
  assign cout = c[16];
endmodule
