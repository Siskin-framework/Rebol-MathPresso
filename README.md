[![rebol-mathpresso](https://github.com/user-attachments/assets/0541d4c8-f5dd-487f-94e4-53c29c44863c)](https://github.com/Siskin-framework/Rebol-MathPresso)

[![Rebol-MathPresso CI](https://github.com/Siskin-framework/Rebol-MathPresso/actions/workflows/main.yml/badge.svg)](https://github.com/Siskin-framework/Rebol-MathPresso/actions/workflows/main.yml)
[![Gitter](https://badges.gitter.im/rebol3/community.svg)](https://gitter.im/rebol3/community?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge)
[![Zulip](https://img.shields.io/badge/zulip-join_chat-brightgreen.svg)](https://rebol.zulipchat.com/)

# Rebol/MathPresso

[Rebol3](https://github.com/Oldes/Rebol3) (3.19.1 and higher) extension for Mathematical Expression Parser And JIT Compiler.
Using Petr Kobalicek's [MathPresso code](https://github.com/kobalicek/mathpresso).

## Usage

This is an example of the initial syntax.

```rebol
mp: import 'mathpresso

;; Initialize a Mathpresso context using a struct containing some double values.
variables!: make struct! [
    unused    [uint64!] ;; this value is ignored by mathpresso expression
    x         [double!]
    y         [double!]
    step      [double!]
    amplitude [double!]
    result    [double!]
]
ctx: mp/context :variables!

;; Compile an expression using the context (or directly the struct)
expr: mp/compile :ctx "y=sin(x); x=x+step; result=round(y*amplitude*100)/100"

;; To evaluate the expression, provide a struct of the same type used during compilation.
data: make variables! [
    unused:    1234     ;; this value should not be affected by the evaluation
    step:      pi / 30  ;; initialize the step onput value using Rebol only 
    amplitude: 100      ;; maximum value of the result
]

;; Evaluate expression (preferably multiple times)
loop 31 [ probe mp/eval :expr :data ]

;; Values in the data struct were updated...
probe data

;; one context may be shared with multiple expressions
expr2: mp/compile :ctx {
    y=sin(x)+cos(x/2);
    x=x+step;
    result=round(y*amplitude*100)/100
}
loop 31 [ probe mp/eval :expr2 :data ]
```

Feel free to [let me know](https://gitter.im/rebol3/community) if something could be improved.

## Extension commands:


#### `context` `:spec`
Initialize MPContext handle with given variable names
* `spec` `[struct!]` Struct with double fields used as expression variables

#### `compile` `:context` `:expression`
Compile math expression using the given context
* `context` `[struct! handle!]` Struct with double fields used by expression as variables or existing MPContext handle
* `expression` `[string!]` Math expression
* `/with`
* `flags` `[integer!]` Optional compilation flags

#### `eval` `:expression` `:variables`
Evaluate precompiled math expressions using given variables
* `expression` `[handle!]` MPExpression
* `variables` `[vector! struct!]` Variables in a double format

#### `set-options` `:flags`
MathPresso options used when expression is being compiled
* `flags` `[integer! none!]` Combination of: 1 = Verbose, 2 = DebugAst, 4 = DebugMachineCode, 8 = DebugCompiler


## Other extension values:
```rebol
;- Options used with the `set-options` command.
kOptionVerbose:          1 ;; Show messages and warnings.
kOptionDebugAst:         2 ;; Debug AST (shows initial and final AST).
kOptionDebugMachineCode: 4 ;; Debug machine code generated.
kOptionDebugCompiler:    8 ;; Debug AsmJit's compiler.
```
