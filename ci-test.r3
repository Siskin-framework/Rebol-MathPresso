Rebol [
    title: "Rebol/MathPresso extension CI test"
    needs: 3.16.0 ;; used the new vector syntax
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

;; print content of the module...
? mp

;; initialize a mathpresso context with given number of input/output variable names
ctx: mp/context [x y step amplitude result]

;; compile an expression using the context
expr: mp/compile :ctx "y=sin(x); x=x+step; result=round(y*amplitude)/100"

;; To evaluate the expression, we need to provide a vector containing double values of count
;; eaqual or greater than number of variables used to create the evaluation context (4 in this case)
data: #(double! [0 0 0 10000 0]) ;; used in the expression like x, y, step, amplitude and result values
data/3: pi / 30                  ;; initialize the step onput value using Rebol only 

;; Evaluate expression (preferably multiple times)
loop 31 [ probe mp/eval :expr :data ]

;; Values in the data vector are updated...
probe data

;; one context may be shared with multiple expressions
expr2: mp/compile :ctx {
    y=sin(x)+cos(x/2);
    x=x+step;
    result=round(y*amplitude)/100
}
loop 31 [ probe mp/eval :expr2 :data ]

print-horizontal-line
print as-yellow "Performance test (comparing naive Rebol version with compiled expression)"

rebol-version: function[data][
    ;; It is not exact version like expr2, because
    ;; the vector is not updated on each step!
    x: data/1
    loop 1000 [
        y: (sin x) + (cos x / 2)
        x: x + data/3
        data/5: (round (y * data/4)) / 100
    ]
    ;; update the vector with the final state
    data/1: x
    data/2: y
    ;; return result as the final value
    data/5
]
mathp-version: function[data][
    loop 1000 [
        mp/eval :expr2 :data
    ]
]
data1: #(double! [0 0 0.1 10000 0])
data2: #(double! [0 0 0.1 10000 0])

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



