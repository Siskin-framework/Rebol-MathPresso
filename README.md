[![rebol-mathpresso](https://github.com/user-attachments/assets/0541d4c8-f5dd-487f-94e4-53c29c44863c)](https://github.com/Siskin-framework/Rebol-MathPresso)

[![Rebol-MathPresso CI](https://github.com/Siskin-framework/Rebol-MathPresso/actions/workflows/main.yml/badge.svg)](https://github.com/Siskin-framework/Rebol-MathPresso/actions/workflows/main.yml)
[![Gitter](https://badges.gitter.im/rebol3/community.svg)](https://gitter.im/rebol3/community?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge)
[![Zulip](https://img.shields.io/badge/zulip-join_chat-brightgreen.svg)](https://rebol.zulipchat.com/)

# Rebol/MathPresso

[Rebol3](https://github.com/Oldes/Rebol3) (3.22.10 and higher) extension for fast evaluation of
mathematical expressions. It uses Petr Kobalicek's [MathPresso](https://github.com/kobalicek/mathpresso),
which parses an expression and compiles it **directly to machine code** (x86, x64 and arm64).

Write the math once as a string, compile it, and then run it as often as you need - typically
thousands or millions of times, at the speed of native code. The expression reads and writes
`double!` fields of a Rebol `struct!`, so there is no conversion of values between Rebol and C.

## Quick start

```rebol
mp: import 'mathpresso

;; 1. Describe the variables as a struct. Every double! field is a variable.
point!: make struct! [
    x [double!]
    y [double!]
    distance [double!]
]

;; 2. Compile an expression which uses them.
expr: mp/compile point! "distance = sqrt(x * x + y * y)"

;; 3. Evaluate it with some data - as often as you need.
p: make point! [x: 3.0 y: 4.0]
mp/eval :expr p    ;== 5.0  (the value of the last statement)
p/distance         ;== 5.0  (the struct was updated)
```

## How it works

There are three steps, and the first two are done just once:

1. **Context** - `mp/context spec` tells MathPresso which variables exist. Each `double!` field
   of the `spec` struct becomes a variable of the same name, placed at the field's position in
   the struct's memory. Fields of other types are not visible to expressions (they keep their
   place in memory, so their values are left untouched).
2. **Compile** - `mp/compile context "..."` turns an expression into machine code. One context may
   be used for any number of expressions. If you pass the struct instead of a context, a context
   is made for you.
3. **Evaluate** - `mp/eval expression data` runs the compiled code on `data`, which must be a struct
   of the same specification as the one used for the context (or a vector of doubles, see below).
   Variables assigned in the expression are written back into `data`.

```rebol
ctx: mp/context point!                       ;; once
len: mp/compile :ctx "sqrt(x * x + y * y)"   ;; once
dbl: mp/compile :ctx "x = x * 2; y = y * 2"  ;; another expression, same context

p: make point! [x: 3.0 y: 4.0]
mp/eval :len p    ;== 5.0
mp/eval :dbl p    ;; p/x is now 6.0, p/y is 8.0
mp/eval :len p    ;== 10.0
```

## The expression language

An expression is a sequence of statements separated by `;`. The value of the whole expression
is the value of its last statement.

```c
var r = sqrt(x * x + y * y);   // `var` declares a local variable (not stored in the struct)
angle = atan2(y, x);           // assignment to a struct field
r * 2                          // the result
```

* **Numbers** are always doubles. Use `//` for comments to the end of a line.
* **Operators:** `+ - * / %` (modulo), `==  !=  <  <=  >  >=`, `!` (not) and parentheses.
  There is no `^` - use `pow(x, y)`.
* **Comparisons give `1` or `0`.** There is no `if`; instead, multiply by a comparison:
  `y = (x > 0) * x` keeps only positive values, and
  `v = v + (age >= life) * (start - v)` sets `v` to `start` only when `age >= life`.
* **Names are case-sensitive:** `Gain` and `gain` are two different names.
* A `var` which is never assigned is `NaN`. An expression with no result gives `NaN` too.

### Built-in constants and functions

| | |
|---|---|
| Constants | `PI`, `E` |
| Rounding | `floor` `ceil` `trunc` `round_even` `round_half_away` `round_half_up` `frac` |
| Basic | `abs` `sqrt` `recip` (1/x) `min` `max` `avg` `copy_sign` `sign_bit` |
| Powers and logs | `pow` `exp` `log` `log2` `log10` |
| Trigonometry | `sin` `cos` `tan` `asin` `acos` `atan` `atan2` `hypot` `sinh` `cosh` `tanh` |
| Checks (give 1 or 0) | `is_nan` `is_inf` `is_finite` |

This extension adds:

| Function | Result |
|---|---|
| `cbrt(x)` `exp2(x)` `expm1(x)` `log1p(x)` | cube root, 2^x, e^x - 1, ln(1 + x) |
| `erf(x)` `erfc(x)` `tgamma(x)` `lgamma(x)` | error function and its complement, gamma, ln of gamma |
| `fmod(x, y)` | remainder of x / y (with the sign of x) |
| `sign(x)` | -1, 0 or 1 |
| `clamp(x, lo, hi)` | x limited to the range lo..hi |
| `mix(a, b, t)` | linear interpolation from a (t = 0) to b (t = 1) |
| `step(edge, x)` | 0 when x < edge, otherwise 1 |
| `smoothstep(e0, e1, x)` | smooth transition from 0 to 1 while x goes from e0 to e1 |
| `hash(x)` | pseudo random number in [0, 1), always the same for the same x |

A struct field or a constant with the same name as one of these functions hides it.

> Note: `round` does not exist - use `round_half_away` for the usual rounding.

## Variables in detail

### Array fields

MathPresso has no indexing, so each element of a `double!` array field becomes its own variable,
named with an underscore and the (1-based) index:

```rebol
tri!: make struct! [v [double! [3]] sum [double!]]
t: make tri! []
t/v: [1.0 2.0 3.0]
mp/eval mp/compile tri! "sum = v_1 + v_2 + v_3" t   ;== 6.0
```

### Constants

Values which do not change between evaluations are better passed as constants than as struct
fields: they need no place in the struct, and MathPresso computes with them already when the
expression is compiled.

```rebol
world: mp/context/with particle! [
    gravity 9.81
    dt      0.016
]
step: mp/compile :world "vy = vy - gravity * dt; y = y + vy * dt"
```

Values must be numbers, so use `compose` or `reduce` for computed ones:
`mp/context/with particle! compose [width (size/x)]`.

A constant's name is a Rebol word, and Rebol words are not case-sensitive - a word may come out
in a different case (whichever spelling of it Rebol met first). For a name which must keep its
exact case, use a ref! instead: `[@Gain 2.5]`.

### Read-only fields

Fields which an expression must not change can be made read-only. Assigning to them is then
reported as an error when the expression is compiled:

```rebol
ctx: mp/context/read-only point! [x y]
mp/compile :ctx "distance = sqrt(x * x + y * y)"   ;; fine
mp/compile :ctx "x = 0"     ;** Can't assign to a read-only variable 'x'. (at 1:3)
```

For an array field, its name makes all its elements read-only. When *every* field is read-only,
the expression can never write into the data, so `eval` then accepts also structs which may not
be written directly (for example a struct which holds Rebol values in `rebval!` fields).

## Evaluating many values at once

### A vector of structs

`eval/each` evaluates an expression for every struct of a vector of structs, in one call. Use it
when you have many items with their own state - particles, sprites, rows of data - and the
expression updates them:

```rebol
particle!: make struct! [x [double!] y [double!] vx [double!] vy [double!]]
particles: make vector! [:particle! 10000]
move: mp/compile particle! "vy = vy - 9.81 * 0.016; x = x + vx * 0.016; y = y + vy * 0.016"

;; every frame:
mp/eval/each :move particles    ;; all 10000 particles move in one call
```

It starts at the vector's current position, `/part` limits the number of elements, and it returns
the result of the last evaluation (or `none` when there was nothing to evaluate).
See [examples/particles.r3](examples/particles.r3) for a complete simulation.

### A vector of doubles

Instead of a struct, `eval` also accepts a vector of 64-bit decimals, in which the values are in
the same order (and at the same byte positions) as the double fields of the struct:

```rebol
v: make vector! [decimal! 64 [3.0 4.0 0.0]]   ;; x, y, distance
mp/eval mp/compile point! "distance = sqrt(x * x + y * y)" v   ;== 5.0
```

## Rendering an image

`render` evaluates an expression once for every pixel of an image and writes the colour into it -
like a pixel shader. The context must be made with `/pixels`, which adds these variables:

| Variable | |
|---|---|
| `x` `y` | the pixel's column and row, from 0 (read-only) |
| `r` `g` `b` | its colour, 0 - 255 (start at 0 for every pixel) |
| `a` | its alpha, 0 - 255 (starts at 255, opaque) |
| `buf` | its value kept by `render/with` (0 without it) |

The colour is rounded and clamped to 0 - 255. The struct holds the values which change between
frames (time, zoom, ...): it is read, never written, so changing them needs no new compilation.

```rebol
frame!: make struct! [t [double!]]
fx: mp/compile mp/context/pixels frame! {
var v = sin(x * 0.05 + t) + sin(y * 0.04 - t);
r = 128 + 127 * sin(v * PI);
g = 128 + 127 * sin(v * PI + 2);
b = 128 + 127 * sin(v * PI + 4);
}
f: make frame! []
img: make image! 320x200
;; every frame:
f/t: f/t + 0.05
mp/render :fx f img
```

`render` starts at the image's position, so `skip img 320` renders from the second row on.

### A value for every pixel

`render/with` takes a vector of 64 or 32-bit decimals, one for every pixel. Before a pixel is evaluated,
its value is read into `buf`, and after it `buf` is written back - so it is kept from one frame to
the next. Trails, glows and densities which fade away are then one line:

```rebol
dens: make vector! [float64! 76800]     ;; 320x240
fade: mp/compile mp/context/pixels frame! {
buf = buf * 0.9;                        // what is not added to again fades
r = min(255, buf * 10);
}
;; every frame: add to `dens` (e.g. hits of points), then
mp/render/with :fade f img dens
```

See [examples/attractor-anim.r3](examples/attractor-anim.r3), where Rebol counts the hits of
points into such a vector and `render/with` fades and colours it.

## When something goes wrong

* An invalid expression is reported as an error with its position (line:column):
  `mp/compile point! "distance = round(x)"` gives `Unresolved symbol round. (at 1:12)`.
* `eval` refuses data of another struct specification, a vector which is too short, and a struct
  which may not be written directly (unless all fields are read-only, see above).
* To see what MathPresso does, use `mp/set-options` with the `kOption*` values below - for example
  `mp/set-options mp/kOptionDebugAst | mp/kOptionDebugMachineCode` prints the parsed expression and
  the generated machine code. `mp/set-options none` turns it off again. `compile/with` uses its own
  flags instead, for just one expression.

## Examples

* [examples/graph2d.reb](examples/graph2d.reb) - draws a 2D function into an image.
* [examples/particles.r3](examples/particles.r3) - three particle fountains, with the whole
  simulation in one expression, saved as frames for a video.
* [examples/mandelbrot.r3](examples/mandelbrot.r3) - the Mandelbrot set, one step of z = z² + c
  for all pixels in each `eval/each` call.
* [examples/shader.r3](examples/shader.r3) - animated pixel effects (plasma, tunnel, metaballs,
  rings, domain warping, the graph2d equation, a Julia set) drawn by `render` in a [Rebol/Pugl](https://github.com/Siskin-framework/Rebol-Pugl)
  window, with controls made by its `widgets.reb`.
* [examples/attractor.r3](examples/attractor.r3) - a Clifford strange attractor drawn by thousands
  of points, with a density based colouring.
* [examples/attractor-anim.r3](examples/attractor-anim.r3) - the same attractor, animated in a
  Rebol/Pugl window: its parameters drift, the expression is compiled again every frame, and
  `render/with` keeps the glowing, fading trails.

Feel free to [let me know](https://gitter.im/rebol3/community) if something could be improved.

## Extension commands:


#### `context` `:spec`
Initialize MPContext handle with given variable names
* `spec` `[struct!]` Struct with double fields used as expression variables (array field `v [double! [3]]` gives `v_1 v_2 v_3`)
* `/with` Add named constants (folded when an expression is compiled)
* `constants` `[block!]` Name/number pairs, e.g. [gain 2.5 offset: 10]; use a ref! (@Gain) to keep the exact case
* `/read-only` Make fields read-only, so an expression assigning to them does not compile
* `fields` `[block!]` Names of double! fields (an array's name covers all its elements). When all are read-only, eval accepts also structs which must not be written raw
* `/pixels` Add variables x y (the pixel, read-only), r g b a (its colour, 0-255) and buf (its value of render/with) for `render`

#### `compile` `:context` `:expression`
Compile math expression using the given context. Besides MathPresso's built-ins, these functions are available: cbrt exp2 expm1 log1p erf erfc tgamma lgamma sign hash (1 argument), fmod step (2), clamp mix smoothstep (3). A struct field or constant of the same name hides the function.
* `context` `[struct! handle!]` Struct with double fields used by expression as variables or existing MPContext handle
* `expression` `[string!]` Math expression
* `/with`
* `flags` `[integer!]` Optional compilation flags

#### `eval` `:expression` `:variables`
Evaluate precompiled math expressions using given variables
* `expression` `[handle!]` MPExpression
* `variables` `[vector! struct!]` Variables in a double format
* `/each` Evaluate for every struct in a vector of structs (from its index); returns the last result
* `/part`
* `count` `[integer!]` Maximum number of elements to evaluate (with /each)

#### `set-options` `:flags`
MathPresso options used when expression is being compiled
* `flags` `[integer! none!]` Combination of the kOption* values; none clears them

#### `render` `:expression` `:data` `:image`
Evaluates an expression for every pixel of an image (from its index) and writes r g b a into it; returns the image
* `expression` `[handle!]` MPExpression compiled with a context made with /pixels
* `data` `[struct!]` Values for the struct's variables - read only, the same for all pixels
* `image` `[image!]` Where x y are its pixel's zero-based column and row; r g b start at 0, a at 255
* `/with` Keep a value for every pixel, as variable buf (else it is 0)
* `buffer` `[vector!]` 32 or 64-bit decimals, one per pixel from the image's index - read before and written after each evaluation


## Other extension values:
```rebol
;- Options used with the `set-options` command.
kOptionVerbose:          1 ;; Show messages and warnings.
kOptionDebugAst:         2 ;; Debug AST (shows initial and final AST).
kOptionDebugMachineCode: 4 ;; Debug machine code generated.
kOptionDebugCompiler:    8 ;; Debug AsmJit's compiler.
;- CPU features which may be excluded from the generated code (X86 only).
;- Meant for testing the code generation - the results do not change.
kOptionDisableSSE4_1: 4096  ;; Do not use SSE4.1 even if the CPU supports it.
kOptionDisableAVX:    8192  ;; Do not use AVX even if the CPU supports it.
kOptionDisableAVX512: 16384 ;; Do not use AVX-512 even if the CPU supports it.
```
