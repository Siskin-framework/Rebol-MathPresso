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
;; A string is compiled from its index, so the leading garbage is skipped.
--test-- "Compiles from the string's index" [
    vd: make variables! [x: 2.0]
    is? mp/eval mp/compile variables! skip "@@@y = x * 3" 3 vd 6.0
]
--rejects-- "A string at its tail (no expression)" [mp/compile variables! tail "y = x"]

;;=============================================================================
group "Compilation flags (compile/with)"

;; With kOptionDisableSSE4_1 the rounding functions are compiled on x86
;; without the SSE4.1 round instruction, so the flag really reaches the code
;; generator - and the results must not change.
round!: make struct! [x [double!] r [double!]]
round-src: "r = floor(x) * 1000 + ceil(x) * 100 + round_half_away(x) * 10 + trunc(x)"
round-all: func [expr /local d][
    collect [
        foreach x [2.5 -2.5 1.3 -1.7] [
            d: make round! compose [x: (x)]
            keep mp/eval :expr d
        ]
    ]
]
--test-- "Results without flags" [
    is? round-all mp/compile round! round-src [2332.0 -3232.0 1211.0 -2121.0]
]
--test-- "Same results with flags given to compile/with" [
    is? round-all mp/compile/with round! round-src mp/kOptionDisableSSE4_1 [2332.0 -3232.0 1211.0 -2121.0]
]
--test-- "Same results with every CPU feature excluded" [
    is? round-all mp/compile/with round! round-src
        mp/kOptionDisableSSE4_1 | mp/kOptionDisableAVX | mp/kOptionDisableAVX512
        [2332.0 -3232.0 1211.0 -2121.0]
]
--test-- "compile/with 0 overrides flags from set-options" [
    mp/set-options mp/kOptionDisableSSE4_1
    result: round-all mp/compile/with round! round-src 0
    mp/set-options 0
    is? result [2332.0 -3232.0 1211.0 -2121.0]
]
--rejects-- "Negative flags"   [mp/compile/with round! round-src -1]
--rejects-- "Too large flags"  [mp/compile/with round! round-src 65536]
--test-- "CPU option values match MathPresso" [
    is? reduce [mp/kOptionDisableSSE4_1 mp/kOptionDisableAVX mp/kOptionDisableAVX512] [4096 8192 16384]
]

;;=============================================================================
group "Options (set-options)"

--test-- "Valid flags are accepted"       [did mp/set-options mp/kOptionDisableAVX]
--test-- "none clears the flags"          [did mp/set-options none]
--test-- "Compiling works after clearing" [
    is? round-all mp/compile round! round-src [2332.0 -3232.0 1211.0 -2121.0]
]
--test-- "Negative flags are refused"     [not mp/set-options -1]
--test-- "Too large flags are refused"    [not mp/set-options 65536]

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

;;=============================================================================
group "Read-only fields (context/read-only)"

--test-- "A read-only field can be read" [
    all [
        handle? roctx: mp/context/read-only kv! [x]
        kd: make kv! [x: 2.0]
        6.0 == mp/eval mp/compile :roctx "y = x * 3" kd
        is? kd/y 6.0
    ]
]
--test-- "Assigning to a read-only field does not compile" [
    all [
        error? err: try [mp/compile :roctx "x = 1"]
        did find form err "read-only"
    ]
]
--test-- "Local variables stay writable" [
    is? mp/eval mp/compile :roctx "var a = x; a = a + 1; y = a" make kv! [x: 2.0] 3.0
]
--test-- "An array's name makes all its elements read-only" [
    all [
        handle? aroctx: mp/context/read-only arr! [v]
        handle? mp/compile :aroctx "s = v_1 + v_3"
        error? try [mp/compile :aroctx "v_1 = 1"]
        error? try [mp/compile :aroctx "v_3 = 1"]
    ]
]
--test-- "/with and /read-only together" [
    is? mp/eval mp/compile mp/context/with/read-only kv! [k 2] [x] "y = x * k" make kv! [x: 4.0] 8.0
]
--rejects-- "A read-only name which is no field"      [mp/context/read-only kv! [nope]]
--rejects-- "A read-only name of a non-double field"  [mp/context/read-only arr! [tag]]
--rejects-- "A read-only name which is no word"       [mp/context/read-only kv! ["x"]]

;; With every variable read-only an expression cannot write into the data,
;; so a struct holding Rebol values (not writable raw) may be read.
pv!: make struct! [x [double!] v [rebval!]]
--test-- "A fully read-only context reads a struct holding Rebol values" [
    pd: make pv! [x: 2.5]
    pd/v: "kept"
    all [
        5.0 == mp/eval mp/compile mp/context/read-only pv! [x] "x * 2" pd
        is? pd/x 2.5
        is? pd/v "kept"
    ]
]
--rejects-- "Without /read-only that struct is still refused" [
    mp/eval mp/compile pv! "x * 2" make pv! [x: 2.5]
]
--rejects-- "A partly read-only context is still refused" [
    mp/eval mp/compile mp/context/read-only make struct! [x [double!] y [double!] v [rebval!]] [x] "x * 2"
        make struct! [x [double!] y [double!] v [rebval!]]
]

;;=============================================================================
group "Extra functions"

fx!: make struct! [x [double!] r [double!]]
;; Compiles `r = <src>` and evaluates it for the given x.
fx: func [src [string!] x [decimal!] /local d][
    d: make fx! compose [x: (x)]
    mp/eval mp/compile fx! join "r = " src d
]
;; libm results need not be exact - cbrt(27) is 3.0000000000000004
near?: func [value expected][
    any [(abs (value - expected)) < 1e-9  ajoin ["got " mold value]]
]

--test-- "cbrt"        [near? fx "cbrt(x)" 27.0 3.0]
--test-- "exp2"        [is? fx "exp2(x)" 10.0 1024.0]
--test-- "expm1 log1p" [is? fx "expm1(x) + log1p(x)" 0.0 0.0]
--test-- "erf erfc"    [is? fx "erf(x) + erfc(x)" 0.0 1.0]
--test-- "tgamma"      [near? fx "tgamma(x)" 5.0 24.0]
--test-- "lgamma"      [near? fx "lgamma(x)" 1.0 0.0]
--test-- "sign"        [is? reduce [fx "sign(x)" -3.0  fx "sign(x)" 0.0  fx "sign(x)" 0.5] [-1.0 0.0 1.0]]
--test-- "fmod"        [is? fx "fmod(x, 2)" 7.5 1.5]
--test-- "step"        [is? reduce [fx "step(0.5, x)" 0.3  fx "step(0.5, x)" 0.7] [0.0 1.0]]
--test-- "clamp"       [is? reduce [fx "clamp(x, 0, 1)" 5.0  fx "clamp(x, 0, 1)" -2.0  fx "clamp(x, 0, 1)" 0.25] [1.0 0.0 0.25]]
--test-- "mix"         [is? fx "mix(2, 4, x)" 0.25 2.5]
--test-- "smoothstep"  [
    is? reduce [fx "smoothstep(0, 1, x)" -1.0  fx "smoothstep(0, 1, x)" 0.5  fx "smoothstep(0, 1, x)" 2.0] [0.0 0.5 1.0]
]
--test-- "hash is the same for the same input" [is? fx "hash(x)" 1.0 fx "hash(x)" 1.0]
--test-- "hash is in [0, 1)" [
    all [h: fx "hash(x)" 1.0  h >= 0.0  h < 1.0]
]
--test-- "hash differs for different inputs" [not equal? fx "hash(x)" 1.0 fx "hash(x)" 2.0]
--test-- "Functions can be nested" [is? fx "clamp(sign(x) * 3, mix(0, 2, 0.5), 2.5)" 1.0 2.5]
;; `variables!` has a field called `step` - it hides the function.
--test-- "A struct field hides a function of the same name" [
    vd: make variables! [step: 2.0]
    is? mp/eval mp/compile variables! "result = step + 1" vd 3.0
]
--test-- "A constant hides a function of the same name" [
    is? mp/eval mp/compile mp/context/with kv! [mix 7] "y = mix" make kv! [] 7.0
]
--rejects-- "A function called with too few arguments"  [mp/compile fx! "r = clamp(x, 1)"]
--rejects-- "A function called with too many arguments" [mp/compile fx! "r = sign(x, 1)"]

;; MathPresso's optimizer kept a variable which held a constant as that
;; constant even after a non-constant value was assigned to it.
--test-- "A variable holding a constant can be assigned a non-constant value" [
    is? mp/eval mp/compile fx! "var n = 0; n = x; r = n" make fx! [x: 3.0] 3.0
]
--test-- "... also when the new value is computed from the old one" [
    is? mp/eval mp/compile fx! "var n = 1; n = n + x; r = n" make fx! [x: 3.0] 4.0
]

;;=============================================================================
group "Rendering into an image (context/pixels and render)"

uni!: make struct! [k [double!]]
pxc: mp/context/pixels uni!
;; The pixel at a zero-based column and row, as a block (so a 3-tuple and a
;; 4-tuple do not compare equal by accident).
px: func [img [image!] p [pair!] /local c][
    c: pick img p + 1x1
    reduce [c/1 c/2 c/3 c/4]
]
grad: mp/compile :pxc "r = x * 10; g = y * 100; b = k"
u: make uni! [k: 7.0]

--test-- "context/pixels gives a context" [handle? pxc]
--test-- "x and y are the pixel's column and row" [
    img: mp/render :grad u make image! 4x2
    all [
        [ 0   0 7 255] = px img 0x0
        [30   0 7 255] = px img 3x0
        [10 100 7 255] = px img 1x1
    ]
]
--test-- "render returns the image" [
    img: make image! 4x2
    same? img mp/render :grad u img
]
--test-- "Struct values are read" [
    u2: make uni! [k: 42.0]
    is? px mp/render :grad u2 make image! 1x1 0x0 [0 0 42 255]
]
--test-- "Unassigned colour is black, opaque" [
    is? px mp/render (mp/compile :pxc "k") u make image! 1x1 0x0 [0 0 0 255]
]
--test-- "Alpha can be assigned" [
    is? px mp/render (mp/compile :pxc "a = 128") u make image! 1x1 0x0 [0 0 0 128]
]
--test-- "Channels are clamped and rounded" [
    is? px mp/render (mp/compile :pxc "r = 300; g = -5; b = 1.5") u make image! 1x1 0x0 [255 0 2 255]
]
--test-- "NaN gives 0" [
    is? px mp/render (mp/compile :pxc "var n; r = n; g = 9") u make image! 1x1 0x0 [0 9 0 255]
]
--test-- "Starts at the image's index, with the right x and y" [
    img: make image! 4x2   ;; white
    mp/render (mp/compile :pxc "r = x; g = y") u skip img 5
    all [
        [255 255 255 255] = px img 0x1   ;; before the index - untouched
        [  1   1   0 255] = px img 1x1
        [  3   1   0 255] = px img 3x1
    ]
]
--test-- "The struct is not written" [
    u3: make uni! [k: 1.0]
    mp/render (mp/compile :pxc "k = 5; r = k") u3 make image! 2x2
    is? u3/k 1.0
]
--test-- "An assigned struct field carries over to the next pixels" [
    ;; The struct is copied once per render, not once per pixel.
    img: mp/render (mp/compile :pxc "k = k + 1; r = k") make uni! [k: 0.0] make image! 3x1
    is? reduce [first px img 0x0  first px img 2x0] [1 3]
]
--test-- "A struct which must not be written raw is accepted" [
    rv!: make struct! [k [double!] v [rebval!]]
    e: mp/compile mp/context/pixels rv! "r = k"
    is? px mp/render :e make rv! [k: 9.0 v: "text"] make image! 1x1 0x0 [9 0 0 255]
]
--test-- "Constants work with /pixels" [
    e: mp/compile mp/context/pixels/with uni! [c 5] "r = c"
    is? first px mp/render :e u make image! 1x1 0x0 5
]
;; render/with keeps a value for every pixel: `buf`.
bufx: mp/compile :pxc "buf = buf * 0.5 + x; r = buf"
--test-- "render/with reads and writes buf" [
    vals: #(float64! [10.0 20.0 30.0 40.0 50.0 60.0 70.0 80.0])
    img: mp/render/with :bufx u make image! 4x2 vals
    all [
        [5.0 11.0 17.0 23.0 25.0 31.0 37.0 43.0] = to block! vals
        11 = first px img 1x0
    ]
]
--test-- "render/with starts at the image's and the vector's index" [
    vals: #(float64! [10.0 20.0 30.0 40.0 50.0 60.0 70.0 80.0])
    mp/render/with :bufx u skip make image! 4x2 6 skip vals 2
    ;; pixels 6 and 7 (x = 2 and 3) use the values 3 and 4:
    ;; 30 * 0.5 + 2 and 40 * 0.5 + 3
    is? to block! vals [10.0 20.0 17.0 23.0 50.0 60.0 70.0 80.0]
]
--test-- "Without /with buf is 0" [
    is? first px mp/render (mp/compile :pxc "r = buf + 3") u make image! 1x1 0x0 3
]
--rejects-- "render/with a vector shorter than the image" [
    mp/render/with :bufx u make image! 4x2 make vector! [float64! 7]
]
--rejects-- "render/with a vector of 32-bit decimals" [
    mp/render/with :bufx u make image! 4x2 make vector! [float32! 8]
]
--rejects-- "A field clashing with buf" [mp/context/pixels make struct! [buf [double!]]]
--rejects-- "Assigning to x"                  [mp/compile :pxc "x = 1"]
--rejects-- "Assigning to y"                  [mp/compile :pxc "y = 1"]
--rejects-- "A field clashing with x"         [mp/context/pixels make struct! [x [double!]]]
--rejects-- "A constant clashing with r"      [mp/context/pixels/with uni! [r 1]]
--rejects-- "render of an expression without /pixels" [
    mp/render (mp/compile uni! "k") u make image! 1x1
]
;; The id is a hash of the specification, so an identical spec (even made
;; anew) is the same struct - this one must differ.
--rejects-- "render with a struct of another spec" [
    mp/render :grad make struct! [j [double!]] make image! 1x1
]
--rejects-- "eval of a /pixels expression on its struct" [mp/eval :grad u]

print-hline
;---------------------------------------------------------------------
print as-yellow "=== Graph2D example ================================"

do %examples/graph2d.reb
image: make image! 640x480
probe delta-time [ graph2d image 19 ]
? image
try [save %graph2d-result.png image]

summary
