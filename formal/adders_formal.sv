// adders_formal.sv - combinational equivalence of every circuit in rtl/ with a behavioural reference, for all inputs
// (2^33 for the 16-bit adders, all valid digit combinations for the 2421 adders). Proved by formal/run_formal.sh.
module adders_formal (
  input logic [15:0] x,
  input logic [15:0] y,
  input logic        cin
);
  // ---------------------------------------------------------------- binary adders: {cout, s} == x + y + cin
  logic [16:0] e;
  logic [4:0]  e4;
  logic [8:0]  e8;
  logic [12:0] e12;
  logic [3:0]  eb;
  assign e   = {1'b0, x} + {1'b0, y} + {16'b0, cin};
  assign e4  = {1'b0, x[3:0]}  + {1'b0, y[3:0]}  + {4'b0, cin};
  assign e8  = {1'b0, x[7:0]}  + {1'b0, y[7:0]}  + {8'b0, cin};
  assign e12 = {1'b0, x[11:0]} + {1'b0, y[11:0]} + {12'b0, cin};
  assign eb  = {e[16], e12[12], e8[8], e4[4]};

  logic [15:0] s_r, s_1, s_2; logic co_r, co_1, co_2; logic [3:0] cb_r, cb_1, cb_2;
  rca16           u_rca (.x, .y, .cin, .s(s_r), .cout(co_r), .cblk(cb_r));
  cla16_single    u_c1  (.x, .y, .cin, .s(s_1), .cout(co_1), .cblk(cb_1));
  cla16_two_level u_c2  (.x, .y, .cin, .s(s_2), .cout(co_2), .cblk(cb_2));
  always_comb begin
    assert ({co_r, s_r} == e && cb_r == eb);
    assert ({co_1, s_1} == e && cb_1 == eb);
    assert ({co_2, s_2} == e && cb_2 == eb);
  end

  // ---------------------------------------------------------------- 2421 adders on valid operands
  function automatic logic valid(input logic [3:0] c);
    valid = (c <= 4'd4) || (c >= 4'd11);
  endfunction
  function automatic logic [3:0] dval(input logic [3:0] c);
    dval = (c <= 4'd4) ? c : c - 4'd6;
  endfunction
  function automatic logic [3:0] enc(input logic [3:0] d);
    enc = (d <= 4'd4) ? d : d + 4'd6;
  endfunction
  logic [15:0] es;
  logic [4:0]  c;              // decimal carries, c[0] = cin
  logic [4:0]  t [4];
  logic        all_valid;
  assign c[0] = cin;
  for (genvar d = 0; d < 4; d++) begin : g_ref
    assign t[d]  = {1'b0, dval(x[4*d +: 4])} + {1'b0, dval(y[4*d +: 4])} + {4'b0, c[d]};
    assign c[d+1] = (t[d] >= 5'd10);
    assign es[4*d +: 4] = enc(c[d+1] ? 4'(t[d] - 5'd10) : t[d][3:0]);
  end
  assign all_valid = valid(x[3:0]) && valid(x[7:4]) && valid(x[11:8]) && valid(x[15:12]) &&
                     valid(y[3:0]) && valid(y[7:4]) && valid(y[11:8]) && valid(y[15:12]);

  logic [15:0] d_r, d_1, d_2; logic dc_r, dc_1, dc_2;
  adder2421 #(.ADDER(0)) u_d0 (.x, .y, .cin, .s(d_r), .cout(dc_r));
  adder2421 #(.ADDER(1)) u_d1 (.x, .y, .cin, .s(d_1), .cout(dc_1));
  adder2421 #(.ADDER(2)) u_d2 (.x, .y, .cin, .s(d_2), .cout(dc_2));
  always_comb begin
    if (all_valid) begin
      assert (d_r == es && dc_r == c[4]);
      assert (d_1 == es && dc_1 == c[4]);
      assert (d_2 == es && dc_2 == c[4]);
    end
  end

  // ---------------------------------------------------------------- two-level circuits: each version is its function
  logic [3:0] v;
  logic [5:0] f;
  logic       fn1, fn2;
  assign v   = x[3:0];
  assign fn1 = (v[1] == v[0]) || (v[1:0] == 2'b01 && v[3]) || (v[1:0] == 2'b10 && !v[3]);
  assign fn2 = (v[1:0] == 2'b00) ? !v[3] : (v[1:0] == 2'b01) ? v[2] : (v[1:0] == 2'b11) ? v[3] : !v[2];
  f1_min u_h0 (.v, .f(f[0]));
  f1_hf  u_h1 (.v, .f(f[1]));
  f1_all u_h2 (.v, .f(f[2]));
  f2_min u_h3 (.v, .f(f[3]));
  f2_hf  u_h4 (.v, .f(f[4]));
  f2_all u_h5 (.v, .f(f[5]));
  always_comb begin
    assert (f[2:0] == {3{fn1}});
    assert (f[5:3] == {3{fn2}});
  end
endmodule
