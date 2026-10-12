# Carry-lookahead and decimal adders, hazard-free two-level logic: lint, simulation (functional, timing, hazards),
# formal equivalence proofs, structural gate counts and synthesis.
# Toolchain: Icarus Verilog, Verilator, Yosys + yosys-abc (exact versions in scripts/install-tools.sh).

GATES := rtl/gates.sv
ADD   := $(GATES) rtl/cla.sv rtl/adder2421.sv
HAZ   := $(GATES) rtl/hazard_free.sv
RUN   := bash scripts/run_sim.sh
TOPS  := cla4 cla16_single cla16_two_level rca16 adder2421 f1_min f1_hf f1_all f2_min f2_hf f2_all

.PHONY: all ci full summary lint sim sim-icarus sim-verilator formal gates synth clean

all: lint sim

# CI entry points (.github/workflows): everything here runs in a few minutes, so both suites are the same
ci: lint sim formal gates synth summary
full: ci

summary:
	@bash scripts/summary.sh > /dev/null && echo "wrote build/SUMMARY.md"

lint:
	@for t in $(TOPS); do echo "verilator --lint-only -Wall --top-module $$t"; \
	  verilator --lint-only -Wall --top-module $$t $(ADD) rtl/hazard_free.sv || exit 1; done

sim: sim-icarus sim-verilator

# functional (zero-delay) tests in both simulators; the gate-delay tests (transport delays) in Icarus
sim-icarus:
	$(RUN) icarus adders tb/tb_adders.sv "" $(ADD)
	$(RUN) icarus timing tb/tb_timing.sv "GATE_DELAYS" $(ADD)
	$(RUN) icarus hazard tb/tb_hazard.sv "GATE_DELAYS" $(HAZ)

sim-verilator:
	$(RUN) verilator adders tb/tb_adders.sv "" $(ADD)

formal:
	bash formal/run_formal.sh

gates:
	bash scripts/gatecount.sh

synth:
	bash scripts/synth.sh

clean:
	rm -rf build obj_dir
