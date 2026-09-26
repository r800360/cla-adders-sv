# Carry-lookahead and decimal adders, hazard-free logic, in gate-level SystemVerilog

This repository contains gate-level adders and two-level logic, each built from an explicit gate library and
analyzed for **function, delay and glitches**:
* 16-bit ripple-carry, single-level and two-level carry-lookahead adders, the CLAs in the *dual* (product-of-sums)
  form;
* a 4-digit **2421** decimal adder on top of each one;
* minimal, hazard-free and all-primes versions of two two-level functions.

Each design is checked in three ways:
* **Formal equivalence:** Yosys SAT proves every adder equal to `x + y + cin` over all 2³³ inputs, and every 2421
  adder equal to decimal addition over all valid digits.
* **Timing:** a transport-delay gate model gives path delays, and a testbench checks them against values derived by
  hand.
* **Glitch scan:** every single-variable input change is applied, and the testbench checks that each static hazard
  appears exactly where the hazard analysis predicts.

## Gate library and delay model

`rtl/gates.sv` holds the cells: NOT, AND and OR of any width, XNOR2, XOR2 and MUX2. Normally they are plain
combinational logic, used for lint, simulation, synthesis and formal. With `+define+GATE_DELAYS` every cell gets a
**transport** delay, in unit-less gate steps:

| NOT | AND/OR, n inputs | XNOR2 | XOR2 | MUX2 |
|:-:|:-:|:-:|:-:|:-:|
| 2 | 5 + (n − 2) | 7 | 9 | 3 |

The delays must be transport, not Verilog's default inertial delay. An inertial delay would swallow the short pulses
that make up a static hazard.

## Carry lookahead in the dual form

The textbook CLA uses `g = xy`, `p = x ⊕ y`, `c+ = g + p·c`. Swapping AND with OR and XOR with XNOR gives an
equivalent form:

```
g*_i = x_i + y_i        p*_i = x_i ⊙ y_i        c_(i+1) = g*_i · (p*_i + c_i)        s_i = p*_i ⊙ c_i
```

Check the three cases:
* x ≠ y: g* = 1 and p* = 0, so the carry propagates;
* x = y = 1: the carry is generated;
* x = y = 0: g* = 0, so the carry is killed.

Unrolled, every carry is a product of sums: two gate levels, at most four inputs per gate.

```
c1 = g0 (p0 + c0)
c2 = g1 (p1 + g0)(p1 + p0 + c0)
c3 = g2 (p2 + g1)(p2 + p1 + g0)(p2 + p1 + p0 + c0)
G* = g3 (p3 + g2)(p3 + p2 + g1)(p3 + p2 + p1 + g0)      P* = p3 + p2 + p1 + p0      c4 = G* (P* + c0)
```

`cla4` is a PG stage (OR2 and XNOR2), the lookahead unit above, and XNOR2 sums. `cla16_single` chains four `cla4`
blocks through their `c4`. `cla16_two_level` feeds the blocks' G*/P* to a **second lookahead unit**, which computes
c4, c8, c12 and c16 at once. `rca16` is a textbook full-adder chain, included for comparison.

### Delays (`tb/tb_timing.sv`)

Two single-input changes that must travel the whole carry chain:
* **V1:** every bit propagates (x = 8888, y = 7777) and the carry-in rises.
* **V2:** bit 0 turns from propagate into generate (x0 rises, y0 = 1), which also goes through the slow XNOR of the
  PG stage.

Settle time of each block carry and of each block's top sum bit:

| | c4 | c8 | c12 | c16 | s3 | s7 | s11 | s15 |
|---|--:|--:|--:|--:|--:|--:|--:|--:|
| V1 ripple-carry | 40 | 80 | 120 | 160 | 39 | 79 | 119 | 159 |
| V1 single-level CLA | 10 | 20 | 30 | 40 | 21 | 31 | 41 | 51 |
| V1 two-level CLA | 10 | 12 | 14 | **10** | 21 | 31 | 33 | **35** |
| V2 single-level CLA | 24 | 34 | 44 | 54 | 28 | 45 | 55 | 65 |
| V2 two-level CLA | 24 | 26 | 28 | **31** | 28 | 45 | 47 | **49** |

Every CLA figure is checked against its derivation:
* **Single level, V1:** each block adds OR2 + AND2 = 10 to the carry (c4 = G*(P* + c_in)).
* **Two-level, V1:** C8 and C12 go through the second-level c2 and c3 paths (OR3 + AND3 = 12, OR4 + AND4 = 14).
  C16 goes through its c4 path (OR2 + AND2 = 10).
* **Sums:** a block's top sum bit settles 21 steps after its carry-in: carry-in → c3 is OR4 + AND4 = 14, then the
  XNOR2 sum adds 7.
* **V2:** the change reaches P*0 after XNOR2 + OR4 = 14. C16 must wait for the second-level P* as well:
  14 + 7 + 5 + 5 = 31.
* **Ripple:** 10 steps per bit (AND2 + OR2).

With 20 000 random input changes, the slowest observed settle times are **148 / 67 / 55** steps for ripple,
single-level and two-level.

### Area (`make gates`)

Structural gate counts from the netlists. "Inputs" is the total number of gate inputs, a proxy for area.

| Design | NOT | AND2 | AND3+ | OR2 | OR3+ | XNOR2 | XOR2 | MUX2 | inputs |
|---|--:|--:|--:|--:|--:|--:|--:|--:|--:|
| cla4 | 0 | 2 | 3 | 9 | 6 | 8 | 0 | 0 | 70 |
| rca16 | 0 | 32 | 0 | 16 | 0 | 0 | 32 | 0 | 160 |
| cla16_single | 0 | 8 | 12 | 36 | 24 | 32 | 0 | 0 | 280 |
| cla16_two_level | 0 | 10 | 15 | 41 | 30 | 32 | 0 | 0 | 326 |
| adder2421 on ripple | 24 | 32 | 16 | 20 | 4 | 0 | 48 | 16 | 336 |
| adder2421 on single-level | 24 | 8 | 28 | 40 | 28 | 32 | 16 | 16 | 456 |
| adder2421 on two-level | 24 | 10 | 31 | 45 | 34 | 32 | 16 | 16 | 502 |

The second lookahead level costs 16 % more gate inputs than the single-level CLA. It cuts the carry-in → c16 delay
from 40 to 10 steps, and the x0 → c16 delay from 54 to 31.

## 2421 decimal adder

In the 2421 code, digits 0–4 are `0000`–`0100` and digits 5–9 are `1011`–`1111` (value + 6). The code is
self-complementing: inverting the bits gives 9 − d. Each digit goes through three steps:

1. **Binary sum:** the 16-bit adder produces X = a + b + c for every digit.
2. **Detection:** X needs correcting exactly when it falls in the invalid range `0101`–`1010`:
   `invalid = X3'X2X1 + X3'X2X0 + X3X2'X1' + X3X2'X0'`.
3. **Correction:** add 6 when the digit produced no binary carry (both digits were low), and subtract 6 when it did
   (both were high). `pm6` does this with five two-input gates and two inverters:
   `z0 = x0`, `z1 = x1'`, `r2 = x1 ⊕ sub`, `z2 = x2' ⊕ r2`, `z3 = x3 ⊕ ((x2 ⊕ sub) + r2)`.

**The binary carry out of each digit is exactly the decimal carry**, so the CLA's block carries serve as the decimal
carries and the corrector stays off the carry path:
* both digits low: X ≤ 9, with neither a binary nor a decimal carry;
* one digit high: X = (a + b + c) + 6, which reaches 16 exactly when a + b + c ≥ 10;
* both digits high: X ≥ 5 + 5 + 12 = 22 always carries, and a + b ≥ 10 is always a decimal carry.

The timing testbench confirms that the decimal carry-out settles exactly when the binary one does. In V1 on the CLAs,
each corrected digit settles one mux delay (3 steps) after the binary sum (s15: 38 against 35 on the two-level CLA).
On the ripple adder the range detector sees the sum bits change later and adds up to 16 steps. For random valid
operands, the slowest settle times are 175 / 91 / 79 steps on ripple, single-level and two-level.

## Hazard-free two-level logic (`rtl/hazard_free.sv`)

Each function comes in three versions: a minimal cover, a minimal cover that is hazard-free except on *allowed
transitions* (input changes the surrounding system never makes), and the cover of all prime terms.

**Why a static hazard depends on direction.** A complemented literal passes through a NOT gate, so it arrives 2 steps
late. Suppose a variable change switches **off** the term that uses its true literal and switches **on** the term that
uses its complement. For 2 steps neither term is on, and an SOP output drops (a static-1 hazard). In the opposite
direction the terms overlap and nothing glitches.

**Function 1 (SOP).** K-map rows CD = 00/01/11/10, columns AB = 00/01/11/10: `1111 / 0011 / 1111 / 1100`.
* **Minimal cover** `A'C + AD + C'D'` glitches on six transitions:
  * C falls at A = D = 0: 0010→0000, 0110→0100;
  * A falls at C = D = 1: 1011→0011, 1111→0111;
  * D falls at A = 1, C = 0: 1001→1000, 1101→1100.
* **Hazard-free cover:** three of those six are not allowed transitions, and covering them takes `A'D'` and `CD`. The
  middle term `A'C` is then redundant, and its own hazards (0011→0010, 0111→0110) are allowed. That leaves
  **`A'D' + AD + C'D' + CD`**: four AND2 and one OR4.
* **All six primes:** no hazard at all.

**Function 2 (POS).** K-map `1100 / 0110 / 0011 / 1001`.
* **Minimal cover** `(A+B+D')(A+B'+C')(A'+B+C)(A'+B'+D)` has a static-0 hazard on 1000→1100, which is not allowed.
* **Hazard-free cover:** one more implicate, `(A'+C+D)`, removes it.
* **All eight prime implicates:** no hazard.

`tb/tb_hazard.sv` applies all 64 single-variable changes to all six circuits under the delay model:

| Circuit | Glitches on |
|---|---|
| f1 minimal | 0010→0000, 0110→0100, 1001→1000, 1011→0011, 1101→1100, 1111→0111 (exactly as predicted) |
| f1 hazard-free | 0011→0010, 0111→0110, 1001→1000, 1101→1100 (all allowed) |
| f1 all primes | none |
| f2 minimal | 0001→1001, 0011→0111, 0110→1110, 1000→1100 (exactly as predicted) |
| f2 hazard-free | 0001→1001, 0011→0111, 0110→1110 (all allowed) |
| f2 all primes | none |

## Verification summary

| Check | Where | Result |
|---|---|---|
| cla4 on all 512 inputs; 16-bit adders on corner patterns and 10⁵ random additions (10⁶ with Verilator); block carries | `tb/tb_adders.sv` (Icarus and Verilator) | pass |
| 2421 adders: every digit pair in every position, with and without carry chains, 10⁴ random 4-digit sums | `tb/tb_adders.sv` | pass |
| Every adder = `x + y + cin` for all 2³³ inputs; every 2421 adder = decimal sum on all valid digits; all six two-level circuits = their K-maps | `formal/` (Yosys + ABC) | **proved** |
| Negative controls: a missing lookahead term; correction selected by the carry instead of the range check | `formal/run_formal.sh` | both fail, as they must |
| Delay figures above | `tb/tb_timing.sv` (Icarus, `GATE_DELAYS`) | match the derivations |
| Glitch table above | `tb/tb_hazard.sv` (Icarus, `GATE_DELAYS`) | matches the analysis |

The gate-delay testbenches run in Icarus only. With Verilator 5.032, the timing testbench's memory use grew past
15 GB.

## Repository layout

```
rtl/gates.sv          gate library (optional transport delays)
rtl/cla.sv            cla_lookahead, cla4, cla16_single, cla16_two_level, rca16
rtl/adder2421.sv      pm6 (add/subtract 6), digit2421_fix, adder2421 (on any of the three binary adders)
rtl/hazard_free.sv    f1/f2: minimal, hazard-free and all-primes covers
tb/                   tb_adders.sv (function), tb_timing.sv (delays), tb_hazard.sv (glitches), tb_common.svh
formal/               adders_formal.sv, pdr.sh, run_formal.sh
scripts/              run_sim.sh, gatecount.sh
```

## Running

```bash
make                 # lint and all simulations
make formal          # equivalence proofs and negative controls
make gates           # structural gate counts
```

Requirements: Verilator 5, Icarus Verilog 12, Yosys ≥ 0.30 with yosys-abc. Tested with Verilator 5.032, Icarus 12.0
and Yosys 0.52.

## Background

These designs started as university digital-design lab assignments, built as schematics. This repository is a
from-scratch re-implementation in SystemVerilog. It adds what the originals lacked: formal proofs, measured delays
and an automated glitch scan.
