# Verification

`make ci` runs every check here in about two minutes. Logs and reports go to `build/`, and `build/SUMMARY.md`
collects them.

| Check | Where | Result |
|---|---|---|
| cla4 on all 512 inputs; 16-bit adders on corner patterns plus 10⁵ random additions (10⁶ in Verilator); block carries | `tb/tb_adders.sv` (Icarus and Verilator) | pass |
| 2421 adders: every digit pair in every position, with and without carry chains, and 10⁴ random 4-digit sums | `tb/tb_adders.sv` | pass |
| Every adder = `x + y + cin` for all 2³³ inputs; every 2421 adder = decimal sum on all valid digits; the six two-level circuits = their K-maps | `formal/` (Yosys + ABC) | proved |
| Negative controls: a missing lookahead term; correction selected by the carry instead of the range check | `formal/run_formal.sh` | both fail, as they must |
| Delay figures in the README and DESIGN.md | `tb/tb_timing.sv` (Icarus, `GATE_DELAYS`) | match the derivations exactly |
| Glitch scan | `tb/tb_hazard.sv` (Icarus, `GATE_DELAYS`) | matches the hazard analysis exactly |

## Delay measurement (`tb/tb_timing.sv`)

The testbench measures each output's **settle time**: the time of its last transition after one input change. Each
change starts from a settled circuit. Two experiments must travel the whole carry chain:
* **V1:** every bit propagates (x = 8888, y = 7777) and the carry-in rises.
* **V2:** bit 0 turns from propagate into generate.

The CLA and ripple figures are checked against the hand-derived values. For the 2421 adders, the checks are that the
decimal carry settles exactly when the binary carry does, and the expected ordering two-level < single-level < ripple.
The 2421 V1/V2 runs use complementary digits (x and y = ~x), which are valid 2421 codes where every bit propagates.

Before measuring, every input is toggled once. The delayed cells only evaluate when an input changes, so without this
step their outputs would stay X.

## Glitch scan (`tb/tb_hazard.sv`)

All 64 single-variable input changes (16 start points × 4 variables) are applied to all six circuits. A static
hazard is an output that starts and ends at the same value but changes in between. The scan checks that:
* every circuit computes its K-map function;
* the all-primes covers never glitch;
* the hazard-free covers glitch only on allowed transitions;
* the minimal covers glitch on **exactly** the predicted transitions.

## Formal (`make formal`)

`formal/adders_formal.sv` places every circuit next to a behavioral reference and asserts that they are equal:
* the binary adders against `x + y + cin`, including their block carries;
* the 2421 adders against digit-by-digit decimal addition, assuming valid input digits;
* the two-level circuits against their K-maps.

The circuits are combinational, so the PDR run reduces to a single SAT proof over all inputs, which takes under a
second. Two broken copies, a missing lookahead term and a wrongly selected correction, must each fail.

## Tools and how they are run

| Tool (version) | Used for | Command |
|---|---|---|
| Icarus Verilog 12.0 | functional, delay and glitch simulation | `iverilog -g2012 -I tb [-DGATE_DELAYS] -o build/<t>.vvp <tb> <rtl>`, then `vvp -n` |
| Verilator 5.032 | lint, functional simulation | `verilator --lint-only -Wall --top-module <top> ...`; `verilator --binary --timing -O2 ...` |
| Yosys 0.52 + ABC | proofs, gate counts, synthesis | `formal/pdr.sh`; `scripts/gatecount.sh`; `scripts/synth.sh` |

* **Proof model.** The flow is `read_verilog -sv -formal; prep; flatten; async2sync; chformal -lower; …;
  write_aiger`, followed by `yosys-abc -c "read_aiger; fold; strash; pdr"`. `chformal -lower` is essential: Yosys 0.52
  turns `assert` into `$check` cells, and without lowering the model would contain no properties at all. `pdr.sh`
  refuses a model with zero properties.
* **Gate counts.** `scripts/gatecount.sh` reads `rtl/gates.sv` as black boxes (`read_verilog -lib`), flattens each
  design, and counts cells by type and fan-in (`select -count t:g_and r:N=<n> %i`).
* **Simulator choice.** The gate-delay testbenches run in Icarus only. With Verilator 5.032 and `--timing`, thousands
  of pending transport events per input change drove the timing testbench past 15 GB of memory.

## CI

The *CI* (`.github/workflows/ci.yml`) and *Full verification* (`full.yml`) workflows both run every target above,
because the whole suite takes minutes:
* CI runs on every push.
* Full verification runs on demand or for a `v*` tag, and a tag also publishes a release.

Both use the pinned `ubuntu:26.04` image and `scripts/install-tools.sh`, the same script as the `Dockerfile`, and upload
`build/` as an artifact.
