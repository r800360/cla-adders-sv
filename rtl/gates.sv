// gates.sv - the gate library every adder and two-level circuit in rtl/ is built from.
//
// Without GATE_DELAYS the cells are plain combinational logic (simulation, lint, synthesis, formal).
// With +define+GATE_DELAYS each cell gets a *transport* delay, so the timing testbenches can measure path delays
// and see static hazards (an inertial delay would swallow the short pulses a hazard produces):
//     NOT 2      AND / OR with n inputs  5 + (n - 2)      XNOR2 7      XOR2 9      MUX2 (select or data) 3
// These are unit-less "gate steps", a simple model in which wider gates and XORs are slower.
// verilator lint_off DECLFILENAME

`ifdef GATE_DELAYS
`define GATE(D, EXPR) always @* y <= #(D) (EXPR);
`else
`define GATE(D, EXPR) always_comb y = (EXPR);
`endif

module g_not (input logic a, output logic y);
  `GATE(2, ~a)
endmodule

module g_and #(parameter int N = 2) (input logic [N-1:0] a, output logic y);
  `GATE(5 + N - 2, &a)
endmodule

module g_or #(parameter int N = 2) (input logic [N-1:0] a, output logic y);
  `GATE(5 + N - 2, |a)
endmodule

module g_xnor2 (input logic a, input logic b, output logic y);
  `GATE(7, ~(a ^ b))
endmodule

module g_xor2 (input logic a, input logic b, output logic y);
  `GATE(9, a ^ b)
endmodule

module g_mux2 (input logic s, input logic d0, input logic d1, output logic y);
  `GATE(3, s ? d1 : d0)
endmodule

`undef GATE
