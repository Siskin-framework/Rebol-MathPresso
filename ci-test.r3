Rebol [
    title: "Rebol/MathPresso extension CI test"
    needs: 3.19.1 ;; used the new struct datatype
]

print ["Running test on Rebol build:" mold to-block system/build]

system/options/quiet: false
system/options/log/rebol: 4

if CI?: any [
    "true" = get-env "CI"
    "true" = get-env "GITHUB_ACTIONS"
    "true" = get-env "TRAVIS"
    "true" = get-env "CIRCLECI"
    "true" = get-env "GITLAB_CI"
][
    ;; configure modules location for the CI test 
    system/options/modules: dirize to-rebol-file any [
        get-env 'REBOL_MODULES_DIR
        what-dir
    ]
    ;; make sure that we load a fresh extension
    try [system/modules/mathpresso: none]
]
mp: import 'mathpresso

;; Print content of the module...
? mp

;; It is possible to modify options used during compilation.
mp/set-options mp/kOptionDebugMachineCode | mp/kOptionDebugAst

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

;; Values in the struct are updated...
probe data

;; One context may be shared with multiple expressions
expr2: mp/compile :ctx {
    y=sin(x)+cos(x/2);
    x=x+step;
    result=round(y*amplitude*100)/100
}
loop 31 [ probe mp/eval :expr2 :data ]

print-horizontal-line
print as-yellow "Performance test (comparing naive Rebol version with compiled expression)"

rebol-version: function[data][
    ;; It is not exact version like expr2, because
    ;; the struct is not updated on each step!
    x: data/x
    loop 1000 [
        y: (sin x) + (cos x / 2)
        x: x + data/step
        data/result: (round (y * data/amplitude * 100)) / 100
    ]
    ;; update the struct with the final state
    data/x: x
    data/y: y
    ;; return result as the final value
    data/result
]
mathp-version: function[data][
    loop 1000 [
        mp/eval :expr2 :data
    ]
]
data1: make variables! [step: 0.1 amplitude: 100]
data2: copy data1

profile [[mathp-version data1][rebol-version data2]]
? data1
? data2
assert [equal? data1 data2]

print-horizontal-line
;---------------------------------------------------------------------
print as-yellow "=== Graph2D example ================================"

do %examples/graph2d.reb
image: make image! 640x480
probe delta-time [ graph2d image 19 ]
? image
try [save %graph2d-result.png image]



