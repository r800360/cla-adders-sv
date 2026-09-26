// hazard_free.sv - two two-level functions, each as a minimal cover (hazardous), a minimal cover that is hazard-free
// except on allowed ("don't-care") transitions, and a cover of all prime terms (hazard-free for every
// single-variable change). One NOT gate per variable provides the complemented literals.
//
// Function 1 (SOP), K-map rows CD = 00 01 11 10, columns AB = 00 01 11 10:
//     1111 / 0011 / 1111 / 1100      primes: A'C  A'D'  AC'  AD  C'D'  CD
// Function 2 (POS):
//     1100 / 0110 / 0011 / 1001      prime implicates: (A+B+D') (A+B'+C') (A+C'+D') (A'+B+C) (A'+B'+D) (A'+C+D)
//                                                      (B+C+D') (B'+C'+D)
// See README.md for the hazard analysis, and tb/tb_hazard.sv for the glitch scan that checks it.
// verilator lint_off DECLFILENAME
// function 1 does not depend on B, so its B' literal is left unused:
// verilator lint_off UNUSEDSIGNAL

module lit4 (input logic [3:0] v, output logic [3:0] n);   // v = {A, B, C, D}, n = complements
  for (genvar i = 0; i < 4; i++) begin : g_n
    g_not u_n (.a(v[i]), .y(n[i]));
  end
endmodule

// f1 = A'C + AD + C'D'  (minimal, 3 terms; static-1 hazards on six transitions)
module f1_min (input logic [3:0] v, output logic f);
  logic a, c, d; logic [3:0] n; logic t0, t1, t2;
  assign {a, c, d} = {v[3], v[1], v[0]};
  lit4 u_l (.v, .n);
  g_and #(2) u_t0 (.a({n[3], c}),    .y(t0));
  g_and #(2) u_t1 (.a({a, d}),       .y(t1));
  g_and #(2) u_t2 (.a({n[1], n[0]}), .y(t2));
  g_or  #(3) u_f  (.a({t0, t1, t2}), .y(f));
endmodule

// f1 = A'D' + AD + C'D' + CD  (4 terms; glitches only on the allowed transitions)
module f1_hf (input logic [3:0] v, output logic f);
  logic a, c, d; logic [3:0] n; logic t0, t1, t2, t3;
  assign {a, c, d} = {v[3], v[1], v[0]};
  lit4 u_l (.v, .n);
  g_and #(2) u_t0 (.a({n[3], n[0]}), .y(t0));
  g_and #(2) u_t1 (.a({a, d}),       .y(t1));
  g_and #(2) u_t2 (.a({n[1], n[0]}), .y(t2));
  g_and #(2) u_t3 (.a({c, d}),       .y(t3));
  g_or  #(4) u_f  (.a({t0, t1, t2, t3}), .y(f));
endmodule

// f1 = all six prime implicants  (no static hazard at all)
module f1_all (input logic [3:0] v, output logic f);
  logic a, c, d; logic [3:0] n; logic [5:0] t;
  assign {a, c, d} = {v[3], v[1], v[0]};
  lit4 u_l (.v, .n);
  g_and #(2) u_t0 (.a({n[3], c}),    .y(t[0]));
  g_and #(2) u_t1 (.a({n[3], n[0]}), .y(t[1]));
  g_and #(2) u_t2 (.a({a, n[1]}),    .y(t[2]));
  g_and #(2) u_t3 (.a({a, d}),       .y(t[3]));
  g_and #(2) u_t4 (.a({n[1], n[0]}), .y(t[4]));
  g_and #(2) u_t5 (.a({c, d}),       .y(t[5]));
  g_or  #(6) u_f  (.a(t),            .y(f));
endmodule

// f2 = (A+B+D')(A+B'+C')(A'+B+C)(A'+B'+D)  (minimal, 4 implicates; a static-0 hazard outside the allowed set)
module f2_min (input logic [3:0] v, output logic f);
  logic a, b, c, d; logic [3:0] n; logic [3:0] t;
  assign {a, b, c, d} = v;
  lit4 u_l (.v, .n);
  g_or  #(3) u_t0 (.a({a, b, n[0]}),       .y(t[0]));
  g_or  #(3) u_t1 (.a({a, n[2], n[1]}),    .y(t[1]));
  g_or  #(3) u_t2 (.a({n[3], b, c}),       .y(t[2]));
  g_or  #(3) u_t3 (.a({n[3], n[2], d}),    .y(t[3]));
  g_and #(4) u_f  (.a(t),                  .y(f));
endmodule

// f2 = the minimal cover plus (A'+C+D)  (5 implicates; glitches only on the allowed transitions)
module f2_hf (input logic [3:0] v, output logic f);
  logic a, b, c, d; logic [3:0] n; logic [4:0] t;
  assign {a, b, c, d} = v;
  lit4 u_l (.v, .n);
  g_or  #(3) u_t0 (.a({a, b, n[0]}),       .y(t[0]));
  g_or  #(3) u_t1 (.a({a, n[2], n[1]}),    .y(t[1]));
  g_or  #(3) u_t2 (.a({n[3], b, c}),       .y(t[2]));
  g_or  #(3) u_t3 (.a({n[3], n[2], d}),    .y(t[3]));
  g_or  #(3) u_t4 (.a({n[3], c, d}),       .y(t[4]));
  g_and #(5) u_f  (.a(t),                  .y(f));
endmodule

// f2 = all eight prime implicates  (no static hazard at all)
module f2_all (input logic [3:0] v, output logic f);
  logic a, b, c, d; logic [3:0] n; logic [7:0] t;
  assign {a, b, c, d} = v;
  lit4 u_l (.v, .n);
  g_or  #(3) u_t0 (.a({a, b, n[0]}),       .y(t[0]));
  g_or  #(3) u_t1 (.a({a, n[2], n[1]}),    .y(t[1]));
  g_or  #(3) u_t2 (.a({a, n[1], n[0]}),    .y(t[2]));
  g_or  #(3) u_t3 (.a({n[3], b, c}),       .y(t[3]));
  g_or  #(3) u_t4 (.a({n[3], n[2], d}),    .y(t[4]));
  g_or  #(3) u_t5 (.a({n[3], c, d}),       .y(t[5]));
  g_or  #(3) u_t6 (.a({b, c, n[0]}),       .y(t[6]));
  g_or  #(3) u_t7 (.a({n[2], n[1], d}),    .y(t[7]));
  g_and #(8) u_f  (.a(t),                  .y(f));
endmodule
