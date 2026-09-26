#!/bin/bash
# run_formal.sh - proves every assertion of formal/adders_formal.sv (the circuits are combinational, so the PDR run
# reduces to one SAT proof over all inputs), then checks that two broken adders are caught.
# Summary: build/formal/summary.txt
cd "$(dirname "$0")/.."
OUTD=build/formal; mkdir -p $OUTD/mutants
OUT=$OUTD/summary.txt; : > $OUT
RTL="rtl/gates.sv rtl/cla.sv rtl/adder2421.sv rtl/hazard_free.sv"
bad=0
check() {  # expected tag files
  local r; r=$(bash formal/pdr.sh "$2" adders_formal "$3")
  local got=${r#*: }; got=${got%% *}
  if [ "$got" = "$1" ]; then echo "  ok        $r" | tee -a $OUT
  else echo "  UNEXPECTED (expected $1) $r" | tee -a $OUT; bad=1; fi
}
mutate() {  # name file sed-expression: writes the mutant and prints the file list that uses it
  sed "$3" "$2" > $OUTD/mutants/$1.sv
  if cmp -s "$2" $OUTD/mutants/$1.sv; then echo "  mutation $1 did not apply" | tee -a $OUT >&2; bad=1; return 1; fi
  echo "$RTL formal/adders_formal.sv" | sed "s#$2#$OUTD/mutants/$1.sv#"
}
echo "== binary adders = x + y + cin; 2421 adders = decimal sum of valid digits; two-level circuits = their K-maps" | tee -a $OUT
check PROVED all "$RTL formal/adders_formal.sv"
echo "== negative controls: each must FAIL" | tee -a $OUT
f=$(mutate c2_missing_term rtl/cla.sv 's/g_and #(3) u_c2  (.a({g\[1\], o2a, o2b}),/g_and #(2) u_c2  (.a({g[1], o2b}),/') \
  && check FAILED mut_c2_missing_term "$f"
f=$(mutate fix_on_carry rtl/adder2421.sv 's/g_mux2 u_m (.s(invalid),/g_mux2 u_m (.s(carry),/') \
  && check FAILED mut_fix_on_carry "$f"
if [ $bad -eq 0 ]; then echo "ALL OUTCOMES AS EXPECTED" | tee -a $OUT; else echo "SOME OUTCOMES UNEXPECTED" | tee -a $OUT; fi
exit $bad
