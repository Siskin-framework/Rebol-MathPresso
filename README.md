
# Rebol/Mathpresso

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
;; eaqual or greater than number of variables used to create the evaluation context (4 in this case)
data: #[double! [0 0 0 10000 0]] ; used in the expression like x, y, step, amplitude and result values
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

Feel free to let me know if something could be improved.