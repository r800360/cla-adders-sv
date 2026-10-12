# Design

## Gate library (`rtl/gates.sv`)

Every circuit is built from explicit cells: NOT, AND and OR of any width, XNOR2, XOR2 and MUX2. Without
`GATE_DELAYS`, the cells are plain combinational logic for lint, simulation, synthesis and proofs. With
`+define+GATE_DELAYS`, each cell gets a **transport** delay, in gate steps:

| NOT | AND / OR with n inputs | XNOR2 | XOR2 | MUX2 |
|:-:|:-:|:-:|:-:|:-:|
| 2 | 5 + (n − 2) | 7 | 9 | 3 |

The delays must be transport, not inertial. An inertial delay, Verilog's default for continuous assignments, would
swallow the short pulses that make up a static hazard. The cells therefore use `always @* y <= #(D) f(inputs)`.

## Carry lookahead in the dual form (`rtl/cla.sv`)

The textbook CLA uses `g = xy`, `p = x ⊕ y` and `c+ = g + p·c`. Swapping AND with OR, and XOR with XNOR, gives an
equivalent form:

```
g*_i = x_i + y_i        p*_i = x_i XNOR y_i        c_(i+1) = g*_i (p*_i + c_i)        s_i = p*_i XNOR c_i
```

The three cases check out:
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

The adders are built from these pieces:
* **`cla4`:** a PG stage (OR2 and XNOR2), the lookahead unit above, and XNOR2 sums.
* **`cla16_single`:** four `cla4` blocks chained through their `c4`.
* **`cla16_two_level`:** feeds the blocks' G*/P* to a second lookahead unit, the same circuit, which computes c4, c8,
  c12 and c16 at once.
* **`rca16`:** a textbook full-adder chain, for comparison.

### Delay derivations

| Path | Derivation | Steps |
|---|---|--:|
| single-level, cin → c4k | each block adds OR2(P*, c) + AND2 | 10 k |
| two-level, cin → c8 / c12 | second-level c2 / c3 paths: OR3 + AND3, OR4 + AND4 | 12 / 14 |
| two-level, cin → c16 | second-level c4 path: OR2 + AND2 | 10 |
| block carry-in → top sum bit | c_in → c3 (OR4 + AND4 = 14), then XNOR2 (7) | + 21 |
| x0 → P*0 (second experiment) | XNOR2 + OR4 | 14 |
| two-level, x0 → c16 | 14, plus second-level P* (OR4, 7), OR2, AND2 | 31 |
| ripple-carry, per bit | AND2 + OR2 | 10 |

The second experiment changes x0 from 0 to 1 with y0 = 1, so bit 0 turns from propagate into generate:

| | c4 | c8 | c12 | c16 | s3 | s7 | s11 | s15 |
|---|--:|--:|--:|--:|--:|--:|--:|--:|
| single-level CLA | 24 | 34 | 44 | 54 | 28 | 45 | 55 | 65 |
| two-level CLA | 24 | 26 | 28 | 31 | 28 | 45 | 47 | 49 |

### Gate counts (`make gates`)

These are structural counts of the netlists as built. "Inputs" is the total number of gate inputs, a proxy for area.

| Design | NOT | AND2 | AND3+ | OR2 | OR3+ | XNOR2 | XOR2 | MUX2 | inputs |
|---|--:|--:|--:|--:|--:|--:|--:|--:|--:|
| cla4 | 0 | 2 | 3 | 9 | 6 | 8 | 0 | 0 | 70 |
| rca16 | 0 | 32 | 0 | 16 | 0 | 0 | 32 | 0 | 160 |
| cla16_single | 0 | 8 | 12 | 36 | 24 | 32 | 0 | 0 | 280 |
| cla16_two_level | 0 | 10 | 15 | 41 | 30 | 32 | 0 | 0 | 326 |
| adder2421 on ripple | 24 | 32 | 16 | 20 | 4 | 0 | 48 | 16 | 336 |
| adder2421 on single-level | 24 | 8 | 28 | 40 | 28 | 32 | 16 | 16 | 456 |
| adder2421 on two-level | 24 | 10 | 31 | 45 | 34 | 32 | 16 | 16 | 502 |

`make synth` re-synthesizes the adders with Yosys and ABC for **area**. That collapses every 16-bit adder to roughly
80–90 generic gates, whatever its structure, so the structural counts above are the ones that match the delay
analysis.

## 2421 decimal adder (`rtl/adder2421.sv`)

In the 2421 code, digits 0–4 are `0000`–`0100` and digits 5–9 are `1011`–`1111` (value + 6). The code is
self-complementing: inverting the bits gives 9 − d.

For each digit, the 16-bit binary adder produces X = a + b + c. X needs correcting exactly when it falls in the
invalid range `0101`–`1010`:

```
invalid = X3' X2 X1 + X3' X2 X0 + X3 X2' X1' + X3 X2' X0'
```

The correction is to add 6 when the digit produced no binary carry (both digits were low), and to subtract 6 when it
did (both were high). `pm6` does this with five two-input gates and two inverters:

```
z0 = x0    z1 = x1'    r2 = x1 XOR sub    z2 = x2' XOR r2    z3 = x3 XOR ((x2 XOR sub) + r2)
```

**The binary carry out of each digit is exactly the decimal carry**, so the corrector stays off the carry path:

| Digits | Binary sum X | Why the carries agree |
|---|---|---|
| both low (0–4) | X ≤ 9 | no binary carry, no decimal carry |
| one high | X = (a + b + c) + 6 | X reaches 16 exactly when a + b + c ≥ 10 |
| both high | X ≥ 5 + 5 + 12 = 22 | always a binary carry, and a + b ≥ 10 is always a decimal carry |

## Hazard-free two-level logic (`rtl/hazard_free.sv`)

**Why a static hazard depends on direction.** A complemented literal passes through a NOT gate, so it arrives 2 steps
late. Suppose a variable change switches **off** the term that uses its true literal and switches **on** the term that
uses its complement. For 2 steps neither term is on, and an SOP output drops. In the opposite direction the two terms
overlap, and nothing glitches.

*Allowed transitions* are input changes the surrounding system never makes, so a glitch there does no harm:
* function 1: 1101→1100, 1001→1000, 1111→0111, 0011→0010, 0111→0110;
* function 2: 1100→1110, 0001→1001, 0011→0111, 0110→1110, 1000→1001.

**Function 1 (SOP).** K-map rows CD = 00/01/11/10, columns AB = 00/01/11/10: `1111 / 0011 / 1111 / 1100`. The prime
implicants are `A'C, A'D', AC', AD, C'D', CD`.
* **Minimal cover** `A'C + AD + C'D'` glitches on six transitions:
  * C falls at A = D = 0: 0010→0000, 0110→0100;
  * A falls at C = D = 1: 1011→0011, 1111→0111;
  * D falls at A = 1, C = 0: 1001→1000, 1101→1100.
* **Hazard-free cover.** Three of those six are not allowed: 0010→0000, 0110→0100 and 1011→0011. Covering them takes
  `A'D'` and `CD`. The middle term `A'C` is then redundant, and its own hazards (0011→0010, 0111→0110) are allowed.
  That leaves **`A'D' + AD + C'D' + CD`**: four AND2 and one OR4.
* **All six primes:** no hazard at all.

**Function 2 (POS).** K-map `1100 / 0110 / 0011 / 1001`. There are eight prime implicates.
* **Minimal cover** `(A+B+D')(A+B'+C')(A'+B+C)(A'+B'+D)` has a static-0 hazard on 1000→1100, which is not allowed.
* **Hazard-free cover:** one more implicate, `(A'+C+D)`, removes it.
* **All eight implicates:** no hazard.
