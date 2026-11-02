Rebol [
    title: "Rebol/MathPresso extension CI test"
    needs: 3.22.10 ;; extension ABI 1 (RL_Struct_Info)
]

print ["Running test on Rebol build:" mold to-block system/build]

system/options/quiet: false
system/options/log/rebol: 4

;;=============================================================================
;; Minimal self-contained harness
;;=============================================================================

test-count: 0
fail-count: 0
skip-count: 0
failed: copy []

group: func ["Starts a named group of tests" name [string!]][
	print ajoin [lf as-yellow "== " as-yellow name]
]

;; NOTE: plain `func` with explicit locals - `function` would collect the
;; counter set-words as locals and the totals would never move.
;;
;; A test block must EVALUATE to true; anything else counts as a failure and
;; is printed as the detail, so a check can hand back a string saying what
;; went wrong. Never use `return` inside one - it would return from
;; `--test--` itself and the result would never be counted.
--test--: func [
	"Passes when the code block evaluates to true"
	name [string!]
	code [block!]
	/local result
][
	test-count: test-count + 1
	result: try code
	case [
		error? :result [
			fail-count: fail-count + 1
			append failed name
			print [as-red "[FAIL]" name]
			print [as-red "      " mold/flat :result]
		]
		:result = true [
			print [as-green "[ ok ]" name]
		]
		true [
			fail-count: fail-count + 1
			append failed name
			print [as-red "[FAIL]" name "=>" mold/flat/part :result 60]
		]
	]
	:result
]

--skip--: func ["Counts a test which cannot run here" name [string!]][
	skip-count: skip-count + 1
	print [as-purple "[skip]" name]
]

--rejects--: func [
	"Checks that the code is refused with an error"
	label [string!]
	code  [block!]
][
	--test-- ajoin [label " is refused"] compose/only [error? try (code)]
]

;; Compares a result with what it should be and hands back the actual value
;; when they differ, so the failure line shows it.
is?: func ["Compares a value with the expected one" value expected][
	any [value == expected  ajoin ["got " mold/flat/part value 60]]
]

summary: does [
	print ajoin [lf as-yellow "-----------------------------------------------------------------------------"]
	print [
		"tests:" test-count
		as-green ajoin ["passed: " test-count - fail-count - skip-count]
		either fail-count > 0 [as-red ajoin ["failed: " fail-count]][ajoin ["failed: " fail-count]]
		as-purple ajoin ["skipped: " skip-count]
	]
	if fail-count > 0 [
		print as-red ajoin ["^/Failed tests:^/  " mold/flat failed]
	]
	print ""
	quit/return either fail-count > 0 [1][0]
]

;;=============================================================================

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
expr: mp/compile :ctx "y=sin(x); x=x+step; result=round_half_away(y*amplitude*100)/100"

;; To evaluate the expression, provide a struct of the same type used during compilation.
data: make variables! compose [
    unused:    1234     ;; this value should not be affected by the evaluation
    step:      (pi / 30) ;; initialize the step input value using Rebol only
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
    result=round_half_away(y*amplitude*100)/100
}
loop 31 [ probe mp/eval :expr2 :data ]

print-hline
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

;;=============================================================================
group "Compiled expression matches Rebol"

--test-- "Compiled and Rebol versions leave the same data" [equal? data1 data2]

;;=============================================================================
group "Compile errors"

--test-- "A valid expression compiles" [handle? mp/compile :ctx "y = x"]
--rejects-- "Invalid syntax" [mp/compile :ctx "y = "]
--test-- "An unknown function is reported by its name" [
    all [
        error? err: try [mp/compile :ctx "y = round(x)"]
        did find form err "round"
    ]
]
--test-- "The error message includes its position" [
    all [
        error? err: try [mp/compile :ctx "y = round(x)"]
        did find form err "(at 1:"
    ]
]
--test-- "The line of a multi-line expression is reported" [
    all [
        error? err: try [mp/compile :ctx "y = x;^/y = foo(x)"]
        did find form err "(at 2:"
    ]
]
--rejects-- "Compiling an invalid expression directly from a struct" [
    mp/compile variables! "y = foo(x)"
]
--test-- "A failed compilation leaves the context usable" [
    handle? mp/compile :ctx "y = x"
]

;;=============================================================================
group "Struct and vector arguments (ABI 1)"

;; A nested struct is a VIEW into its parent's data at a non-zero offset,
;; so its data and size must come from its own specification.
outer: make struct! [
    tag [uint8!]
    v   [struct! [a [double!] b [double!] r [double!]]]
]
outer/tag: 7
outer/v/a: 1.5
outer/v/b: 2.0

--test-- "Compile against a nested struct view" [
    handle? nexpr: mp/compile outer/v "r = a + b"
]
--test-- "Evaluate with a nested struct view" [is? mp/eval :nexpr outer/v 3.5]
--test-- "The view's field is written"        [is? outer/v/r 3.5]
--test-- "The byte in front of the view is left alone" [is? outer/tag 7]

;; A struct holding Rebol values must not be written by raw bytes.
p: make struct! [x [double!] v [rebval!]]
--test-- "Compile against a struct holding Rebol values" [
    handle? pexpr: mp/compile p "x = x + 1"
]
--rejects-- "Writing into a struct holding Rebol values" [mp/eval :pexpr p]
--test-- "The refused struct keeps its data" [is? p/x 0.0]

;; A vector of doubles may be used instead of the struct.
--test-- "Compile for use with a vector" [
    handle? vexpr: mp/compile make struct! [a [double!] b [double!] r [double!]] "r = a * b"
]
vec: make vector! [decimal! 64 [3.0 4.0 0.0]]
--test-- "Evaluate with a vector of doubles" [is? mp/eval :vexpr :vec 12.0]
--test-- "The vector is written"             [is? vec/3 12.0]
--rejects-- "A vector of integers"           [mp/eval :vexpr make vector! [integer! 32 [1 2 3]]]
--rejects-- "A too short vector"             [mp/eval :vexpr make vector! [decimal! 64 [1.0]]]

;; The variables of `variables!` end at byte 48 (a uint64! comes first), so
;; 5 doubles are not enough although the struct has only 5 double fields.
--test-- "Compile with a non-double field before the variables" [
    handle? uexpr: mp/compile variables! "result = x + step"
]
--rejects-- "A vector shorter than the last variable's end" [
    mp/eval :uexpr make vector! [decimal! 64 [0.0 1.0 0.0 2.0 0.0]]
]
--test-- "A vector reaching the last variable's end" [
    uvec: make vector! [decimal! 64 [0.0 1.0 0.0 2.0 0.0 0.0]]
    all [
        3.0 == mp/eval :uexpr uvec
        is? uvec/6 3.0
    ]
]
--test-- "The size counts from the vector's index" [
    uvec: make vector! [decimal! 64 [9.0 0.0 1.0 0.0 2.0 0.0 0.0]]
    all [
        3.0 == mp/eval :uexpr next uvec
        is? uvec/1 9.0
    ]
]
;; A vector value whose index is past its tail - the series was shortened
;; after the value was taken.
--test-- "A vector with its index past the tail is refused" [
    uvec: make vector! [decimal! 64 [0.0 1.0 0.0 2.0 0.0 0.0 0.0 0.0]]
    past: skip uvec 7
    clear uvec
    all [
        empty? head past
        error? try [mp/eval :uexpr past]
    ]
]
--rejects-- "A vector too short from its index" [
    mp/eval :uexpr skip make vector! [decimal! 64 [0.0 1.0 0.0 2.0 0.0 0.0]] 1
]
--rejects-- "A struct of another specification" [mp/eval :vexpr outer]

;;=============================================================================
group "Evaluating a vector of structs (eval/each)"

pt!:    make struct! [a [double!] b [double!] r [double!]]
other!: make struct! [x [double!] y [double!]]
--test-- "Compile for use with a vector of structs" [
    handle? sexpr: mp/compile pt! "r = a * b"
]
vs: make vector! [:pt! 3]
v: 0.0 foreach s vs [s/a: v + 1 s/b: v: v + 2]

--test-- "Returns the last result" [is? mp/eval/each :sexpr vs 30.0]
--test-- "Every element is written" [
    is? reduce [vs/1/r vs/2/r vs/3/r] [2.0 12.0 30.0]
]
--test-- "/part limits the number of elements" [
    vs/1/r: 0.0  vs/2/r: 0.0  vs/3/r: 0.0
    all [
        12.0 == mp/eval/each/part :sexpr vs 2
        is? reduce [vs/1/r vs/2/r vs/3/r] [2.0 12.0 0.0]
    ]
]
--test-- "/part larger than the vector stops at its tail" [
    is? mp/eval/each/part :sexpr vs 10 30.0
]
--test-- "Evaluation starts at the vector's index" [
    vs/1/r: 0.0
    all [
        30.0 == mp/eval/each :sexpr skip vs 2
        is? vs/1/r 0.0
    ]
]
--test-- "Nothing to evaluate returns none" [none? mp/eval/each :sexpr tail vs]
--test-- "/part 0 returns none"             [none? mp/eval/each/part :sexpr vs 0]
--test-- "Same results as evaluating each element on its own" [
    v2: make vector! [:pt! 2]
    v2/1: make pt! [ 1.5 2.0]
    v2/2: make pt! [-3.0 0.5]
    mp/eval/each :sexpr v2
    either system/version > 3.22.12 [
        is? reduce [v2/1/r v2/2/r] reduce [mp/eval :sexpr v2/1  mp/eval :sexpr v2/2]
    ][  is? reduce [v2/1/r v2/2/r] [3.0 -1.5] ]
    
]
--rejects-- "/each with a vector of doubles" [
    mp/eval/each :sexpr make vector! [decimal! 64 [1.0 2.0 0.0]]
]
--rejects-- "/each with a single struct" [mp/eval/each :sexpr make pt! []]
--rejects-- "Elements of another specification" [mp/eval/each :sexpr make vector! [other! 2]]
--rejects-- "A vector of structs without /each" [mp/eval :sexpr vs]

;;=============================================================================
group "Constants (context/with)"

kv!: make struct! [x [double!] y [double!]]
--test-- "Constants are usable in expressions" [
    all [
        handle? cctx:  mp/context/with kv! [gain 2.5 offset: 10]
        handle? cexpr: mp/compile :cctx "y = x * gain + offset"
        kd: make kv! [x: 2.0]
        15.0 == mp/eval :cexpr kd
        is? kd/y 15.0
    ]
]
--test-- "A context with constants can be shared" [
    kd: make kv! [x: 4.0]
    is? mp/eval mp/compile :cctx "x - offset" kd -6.0
]
--test-- "A context without /with has no constants" [
    error? try [mp/compile mp/context kv! "y = x * gain"]
]
;; MathPresso names are case-sensitive, while Rebol words are not: a word
;; arrives in its canonical spelling (the first casing Rebol met), so the
;; word `scale` below turns `Scale` into `scale`. A ref! keeps the name as
;; written.
scale: none
--test-- "A ref! constant keeps the case it is written in" [
    is? mp/eval mp/compile mp/context/with kv! [@Scale 3] "x * Scale" make kv! [x: 2.0] 6.0
]
--test-- "A word constant takes its canonical spelling" [
    is? mp/eval mp/compile mp/context/with kv! [Scale 3] "x * scale" make kv! [x: 2.0] 6.0
]
--test-- "Ref! and word names can be mixed" [
    is? mp/eval mp/compile mp/context/with kv! [@Gain 2 offset 1] "x * Gain + offset" make kv! [x: 2.0] 5.0
]
--rejects-- "A constant without a value"       [mp/context/with kv! [gain]]
--rejects-- "A constant which is not a number" [mp/context/with kv! [gain "2.5"]]
--rejects-- "A constant named by a number"     [mp/context/with kv! [1 2]]
--rejects-- "A constant named by a string"     [mp/context/with kv! ["gain" 2]]
--rejects-- "A constant named like a field"    [mp/context/with kv! [x 1]]
--rejects-- "A constant named like a built-in" [mp/context/with kv! [@PI 3]]  ;; a word would become `pi`
--rejects-- "Assigning to a constant"          [mp/compile :cctx "gain = 1"]

;;=============================================================================
group "Array fields"

;; `v [double! [3]]` becomes the variables `v_1`, `v_2` and `v_3`.
arr!: make struct! [tag [uint8!] v [double! [3]] s [double!]]
--test-- "Array elements are usable as variables" [
    all [
        handle? aexpr: mp/compile arr! "s = v_1 + v_2 * v_3"
        ad: make arr! [tag: 7]
        ad/v: [1.0 2.0 3.0]
        7.0 == mp/eval :aexpr ad
        is? ad/s 7.0
    ]
]
--test-- "Array elements can be written" [
    all [
        mp/eval mp/compile arr! "v_3 = v_1 + v_2" ad
        is? pick ad/v 3 3.0
    ]
]
--test-- "Writing the last element leaves the next field alone" [
    ad/s: 42.0
    mp/eval mp/compile arr! "v_3 = 100" ad
    all [is? ad/s 42.0  is? ad/tag 7]
]
--test-- "Elements are counted from 1" [
    error? try [mp/compile arr! "s = v_0"]
]
--test-- "There is no element past the array" [
    error? try [mp/compile arr! "s = v_4"]
]
--test-- "The array itself is not a variable" [
    error? try [mp/compile arr! "s = v"]
]
--test-- "Arrays of other types are ignored" [
    handle? mp/compile make struct! [i [int32! [2]] s [double!]] "s = 1"
]
--test-- "A vector of doubles covers the array too" [
    vd: make vector! [decimal! 64 [1.0 2.0 3.0 0.0]]
    is? mp/eval mp/compile make struct! [v [double! [3]] s [double!]] "s = v_1 + v_2 + v_3" vd 6.0
]
--rejects-- "An element named like a plain field" [
    mp/context make struct! [v_1 [double!] v [double! [2]]]
]
--rejects-- "A plain field named like an element" [
    mp/context make struct! [v [double! [2]] v_1 [double!]]
]
--rejects-- "A plain field named like a built-in" [
    mp/context make struct! [sin [double!]]
]
--test-- "Plain fields still work after the change" [
    is? mp/eval mp/compile kv! "y = x * 2" make kv! [x: 1.5] 3.0
]

print-hline
;---------------------------------------------------------------------
print as-yellow "=== Graph2D example ================================"

do %examples/graph2d.reb
image: make image! 640x480
probe delta-time [ graph2d image 19 ]
? image
try [save %graph2d-result.png image]

summary
