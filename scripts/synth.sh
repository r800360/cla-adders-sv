#!/bin/bash
# synth.sh - Yosys synthesis of every adder to a generic gate library (synth -flatten; abc -g gates), for comparison
# with the hand-built structure (scripts/gatecount.sh). Writes build/synth/<design>.txt (statistics), <design>.v
# (netlist) and summary.txt.
cd "$(dirname "$0")/.."
B=build/synth; mkdir -p $B
F="rtl/gates.sv rtl/cla.sv rtl/adder2421.sv rtl/hazard_free.sv"
printf '%-22s %6s %6s %6s\n' design gates inv total | tee $B/summary.txt
one() {  # name top [chparam]
  local ch=""; [ -n "${3:-}" ] && ch="chparam $3 $2;"
  yosys -q -p "read_verilog -sv $F; $ch synth -top $2 -flatten; abc -g gates; opt_clean; \
    tee -q -o $B/$1.txt stat; write_verilog -noattr $B/$1.v" > $B/$1.log 2>&1 < /dev/null \
    || { echo "$1: yosys failed (see $B/$1.log)"; return; }
  awk -v n="$1" '/^ +\$_/ { c=$1; v=$2; if (c=="$_NOT_") inv+=v; else g+=v }
    END { printf "%-22s %6d %6d %6d\n", n, g, inv, g+inv }' $B/$1.txt | tee -a $B/summary.txt
}
one rca16 rca16
one cla16_single cla16_single
one cla16_two_level cla16_two_level
one adder2421_two_level adder2421 "-set ADDER 2"
