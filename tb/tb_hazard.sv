// tb_hazard.sv - static-hazard scan of rtl/hazard_free.sv under the gate-delay model (compile with GATE_DELAYS).
//
// Every one of the 64 single-variable input changes (16 start points x 4 variables) is applied to all six circuits;
// an output that starts and ends at the same value but changes in between is a static hazard (a glitch).
// Allowed transitions ("transition don't-cares": the system never makes them, so a glitch there does no harm):
//   function 1: 1101->1100  1001->1000  1111->0111  0011->0010  0111->0110
//   function 2: 1100->1110  0001->1001  0011->0111  0110->1110  1000->1001
// Checks: every circuit computes its K-map function; the all-primes covers never glitch; the hazard-free covers
// glitch only on allowed transitions; the minimal covers glitch exactly where the analysis in README.md predicts.
`timescale 1ns/1ns
`include "tb_common.svh"

module tb_hazard;
  logic [3:0] v = '0;
  logic [5:0] f;                     // f1_min f1_hf f1_all f2_min f2_hf f2_all
  f1_min u0 (.v, .f(f[0]));
  f1_hf  u1 (.v, .f(f[1]));
  f1_all u2 (.v, .f(f[2]));
  f2_min u3 (.v, .f(f[3]));
  f2_hf  u4 (.v, .f(f[4]));
  f2_all u5 (.v, .f(f[5]));

  int changes [6];
  for (genvar i = 0; i < 6; i++) begin : g_cnt
    always @(f[i]) changes[i]++;
  end

  // K-maps, minterm index {A,B,C,D}
  function automatic bit fn1(input logic [3:0] m);
    return (m[1] == m[0]) || (m[1:0] == 2'b01 && m[3]) || (m[1:0] == 2'b10 && !m[3]);
  endfunction
  function automatic bit fn2(input logic [3:0] m);
    case (m[1:0]) 2'b00: return !m[3]; 2'b01: return m[2]; 2'b11: return m[3]; default: return !m[2]; endcase
  endfunction
  function automatic bit tdc(input int fnum, input logic [3:0] a, input logic [3:0] b);
    if (fnum == 1)
      case ({a, b}) 8'hDC, 8'h98, 8'hF7, 8'h32, 8'h76: return 1'b1; default: return 1'b0; endcase
    case ({a, b}) 8'hCE, 8'h19, 8'h37, 8'h6E, 8'h89: return 1'b1; default: return 1'b0; endcase
  endfunction
  // glitches predicted for the minimal covers (README.md)
  function automatic bit predicted_min(input int fnum, input logic [3:0] a, input logic [3:0] b);
    if (fnum == 1)
      case ({a, b}) 8'h20, 8'h64, 8'hB3, 8'hF7, 8'h98, 8'hDC: return 1'b1; default: return 1'b0; endcase
    case ({a, b}) 8'h19, 8'h37, 8'h6E, 8'h8C: return 1'b1; default: return 1'b0; endcase
  endfunction

  function automatic string names(input int i);
    case (i)
      0: return "f1 minimal"; 1: return "f1 hazard-free"; 2: return "f1 all primes";
      3: return "f2 minimal"; 4: return "f2 hazard-free"; default: return "f2 all primes";
    endcase
  endfunction
  int e_func [6], e_bad [6], n_glitch [6], e_pred [6];
  string glist [6];
  initial begin
    for (int i = 0; i < 6; i++) begin e_func[i] = 0; e_bad[i] = 0; n_glitch[i] = 0; e_pred[i] = 0; glist[i] = ""; end
    v = 4'hF; #100; v = 4'h0; #100;      // the delayed gates only evaluate on input changes: settle every gate first
    for (int st = 0; st < 16; st++) begin
      for (int k = 0; k < 4; k++) begin
        logic [3:0] a, b;
        a = 4'(st); b = a ^ (4'b1000 >> k);
        v = a; #100;
        for (int i = 0; i < 6; i++) begin
          if (f[i] !== ((i < 3) ? fn1(a) : fn2(a))) e_func[i]++;
          changes[i] = 0;
        end
        v = b; #100;
        for (int i = 0; i < 6; i++) begin
          int fnum; bit static_t, glitch;
          fnum = (i < 3) ? 1 : 2;
          static_t = (fnum == 1) ? (fn1(a) == fn1(b)) : (fn2(a) == fn2(b));
          glitch = static_t && changes[i] > 0;
          if (!static_t && changes[i] != 1) e_bad[i]++;                  // a dynamic hazard (never expected)
          if (glitch) begin
            n_glitch[i]++;
            glist[i] = $sformatf("%s %b->%b", glist[i], a, b);
            if ((i % 3) != 2 && (i % 3) != 0 && !tdc(fnum, a, b)) e_bad[i]++;   // hazard-free cover
            if ((i % 3) == 2) e_bad[i]++;                                     // all primes: never
          end
          if ((i % 3) == 0 && glitch != predicted_min(fnum, a, b)) e_pred[i]++;
        end
      end
    end
    for (int i = 0; i < 6; i++) begin
      $display("  %-15s glitches on %0d transitions:%s", names(i), n_glitch[i], glist[i]);
      `CHECK("FUNC", $sformatf("%s computes its K-map function", names(i)), e_func[i] == 0,
             $sformatf("%0d wrong minterms", e_func[i]))
      if (i % 3 == 0)
        `CHECK("FUNC", $sformatf("%s glitches exactly on the predicted transitions", names(i)),
               e_pred[i] == 0 && e_bad[i] == 0, $sformatf("%0d transitions differ from the prediction", e_pred[i]))
      else if (i % 3 == 1)
        `CHECK("FUNC", $sformatf("%s glitches only on allowed transitions", names(i)), e_bad[i] == 0,
               $sformatf("%0d glitches on transitions that are not allowed", e_bad[i]))
      else
        `CHECK("FUNC", $sformatf("%s never glitches", names(i)), e_bad[i] == 0,
               $sformatf("%0d glitches", e_bad[i]))
    end
    `REPORT
    $finish;
  end
endmodule
