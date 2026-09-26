#!/bin/bash
# gatecount.sh - structural gate count of every design: the gate cells of rtl/gates.sv are read as black boxes, the
# design is flattened, and the cells are counted by type and fan-in. "inputs" is the total number of gate inputs.
cd "$(dirname "$0")/.."
B=build/gates; mkdir -p $B
printf '%-22s %5s %5s %5s %5s %5s %5s %5s %5s %7s\n' design NOT AND2 AND3+ OR2 OR3+ XNOR2 XOR2 MUX2 inputs \
  | tee $B/summary.txt
count() {  # name top files [chparam]
  local name=$1 top=$2 files=$3 ch="" sel="" out=$B/$1.txt
  [ -n "${4:-}" ] && ch="chparam $4 $top;"
  rm -f "$out"
  for t in g_not g_xnor2 g_xor2 g_mux2; do sel="$sel tee -q -a $out select -count t:$t;"; done
  for n in 2 3 4 5 6 7 8; do
    sel="$sel tee -q -a $out select -count t:g_and r:N=$n %i; tee -q -a $out select -count t:g_or r:N=$n %i;"
  done
  yosys -q -p "read_verilog -sv -lib rtl/gates.sv; read_verilog -sv $files; $ch hierarchy -top $top; flatten; $sel" \
    > /dev/null 2>&1 < /dev/null || { echo "$name: yosys failed"; return; }
  [ -s "$out" ] || { echo "$name: no counts"; return; }
  grep -oE "[0-9]+ objects" "$out" | awk '{print $1}' | tr '\n' ' ' | awk -v n="$name" '{
    not_ = $1; xnor = $2; xor_ = $3; mux = $4; a2 = $5; o2 = $6; a3 = 0; o3 = 0
    ins = not_ + 2 * xnor + 2 * xor_ + 3 * mux
    for (k = 0; k < 7; k++) { a = $(5 + 2 * k); o = $(6 + 2 * k); ins += (k + 2) * (a + o); if (k > 0) { a3 += a; o3 += o } }
    printf "%-22s %5d %5d %5d %5d %5d %5d %5d %5d %7d\n", n, not_, a2, a3, o2, o3, xnor, xor_, mux, ins }' \
    | tee -a $B/summary.txt
}
count cla4                cla4            rtl/cla.sv
count rca16               rca16           rtl/cla.sv
count cla16_single        cla16_single    rtl/cla.sv
count cla16_two_level     cla16_two_level rtl/cla.sv
count adder2421_ripple    adder2421 "rtl/cla.sv rtl/adder2421.sv" "-set ADDER 0"
count adder2421_single    adder2421 "rtl/cla.sv rtl/adder2421.sv" "-set ADDER 1"
count adder2421_two_level adder2421 "rtl/cla.sv rtl/adder2421.sv" "-set ADDER 2"
for f in f1_min f1_hf f1_all f2_min f2_hf f2_all; do count $f $f rtl/hazard_free.sv; done
