[![rebol-mathpresso](https://github.com/user-attachments/assets/0541d4c8-f5dd-487f-94e4-53c29c44863c)](https://github.com/Siskin-framework/Rebol-MathPresso)

[![Rebol-MathPresso CI](https://github.com/Siskin-framework/Rebol-MathPresso/actions/workflows/main.yml/badge.svg)](https://github.com/Siskin-framework/Rebol-MathPresso/actions/workflows/main.yml)
[![Gitter](https://badges.gitter.im/rebol3/community.svg)](https://gitter.im/rebol3/community?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge)
[![Zulip](https://img.shields.io/badge/zulip-join_chat-brightgreen.svg)](https://rebol.zulipchat.com/)

# Rebol/MathPresso

[Rebol3](https://github.com/Oldes/Rebol3) extension for Mathematical Expression Parser And JIT Compiler.
Using Petr Kobalicek's [MathPresso code](https://github.com/kobalicek/mathpresso).

## Usage

This is an example of the initial syntax.

```rebol
mp: import 'mathpresso

;; initialize a mathpresso context with given number of input/output variable names
ctx: mp/context [x y step amplitude result]

;; compile an expression using the context
expr: mp/compile :ctx "y=sin(x); x=x+step; result=round(y*amplitude)/100"

;; To evaluate the expression, we need to provide a vector containing double values of count
;; eaqual or greater than number of variables used to create the evaluation context (5 in this case)
data: #(double! [0 0 0 10000 0]) ; used in the expression like x, y, step, amplitude and result values

;; initialize the step onput value using Rebol only 
data/3: pi / 30

;; Evaluate expression (preferably multiple times)
loop 31 [ probe mp/eval :expr :data ]

;; Values in the data vector are updated...
probe data

;; one context may be shared with multiple expressions
expr2: mp/compile :ctx "y=sin(x)+cos(x/2); x=x+step; result=round(y*amplitude)/100"
loop 31 [ probe mp/eval :expr2 :data ]
```

Feel free to [let me know](https://gitter.im/rebol3/community) if something could be improved.

## Extension commands:


#### `context` `:spec`
Initialize MPContext handle with given variable names
* `spec` `[block!]` Block with variable names used by expressions

#### `compile` `:context` `:expression`
Compile math expression using the given context
* `context` `[handle!]` MPContext
* `expression` `[string!]` Math expression

#### `eval` `:expression` `:variables`
Evaluate precompiled math expressions using given variables
* `expression` `[handle!]` MPExpression
* `variables` `[vector!]` Variables in a double format

