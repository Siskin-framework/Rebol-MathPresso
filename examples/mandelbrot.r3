Rebol [
    title:   "Mandelbrot set"
    file:    %mandelbrot.r3
    purpose: {
        Demonstrates `eval/each` and constants of the Rebol/MathPresso
        extension.

        Every pixel is a struct holding its point `c` of the complex plane
        and the current value of `z`. One `eval/each` call performs ONE step
        of z = z^2 + c for all pixels at once; repeating it gives the whole
        picture. MathPresso has no loops and no `if`, so a pixel which
        escaped is "frozen" by multiplying its change by a comparison.
    }
    needs:   3.22.10
    license: MIT
    url:     https://github.com/Siskin-framework/Rebol-MathPresso
]

mp: import 'mathpresso

size:       800x500
iterations: 600
out-file:   %mandelbrot.png

;; The part of the complex plane to show: its centre and its width.
;; Seahorse valley:
center: -0.7436439x0.1318259
width:  0.012
;; The whole set (needs only about 200 iterations):
;center: -0.6x0   width: 3.2

;; State of one pixel.
pixel!: make struct! [
    cr [double!]  ci [double!]   ;; the point c = cr + ci*i
    zr [double!]  zi [double!]   ;; z, starting at 0
    n  [double!]                 ;; number of steps before z escaped
    r  [double!]  g [double!]  b [double!]   ;; colour computed at the end
]

ctx: mp/context/with pixel! compose [
    bailout    256.0          ;; |z|^2 beyond which z escapes (large for smooth colours)
    iterations (iterations)
]

;; One step of z = z^2 + c for a pixel still inside the bailout radius.
;; A pixel which escaped keeps its last z, so its `n` and `z` are what the
;; smooth colouring needs.
iterate: mp/compile :ctx {
var zr2 = zr * zr;
var zi2 = zi * zi;
var inside = zr2 + zi2 <= bailout;
var nzi = 2 * zr * zi + ci;
zr = zr + inside * (zr2 - zi2 + cr - zr);
zi = zi + inside * (nzi - zi);
n  = n + inside;
}

;; Smooth (continuous) iteration count, then a cosine palette.
;; Pixels which never escaped are inside the set and black.
shade: mp/compile :ctx {
var escaped = n < iterations;
var m  = max(zr * zr + zi * zi, 1.0001);
var mu = n + 1 - log2(0.5 * log(m));
var t  = sqrt(max(mu, 0)) * 0.16 + 0.55;
r = escaped * 255 * (0.5 + 0.5 * cos(2 * PI * (t + 0.00)));
g = escaped * 255 * (0.5 + 0.5 * cos(2 * PI * (t + 0.10)));
b = escaped * 255 * (0.5 + 0.5 * cos(2 * PI * (t + 0.20)));
}

w: size/x
h: size/y
pixels: make vector! reduce [:pixel! to integer! w * h]

print "Preparing pixels..."
prepare-time: delta-time [
    left: center/x - (width / 2)
    top:  center/y + (width * h / w / 2)
    unit: width / w
    i: 1
    repeat y h [
        ci: top - (y - 1 * unit)
        repeat x w [
            p: pixels/(++ i)
            p/cr: left + (x - 1 * unit)
            p/ci: ci
        ]
    ]
]

print ["Iterating" iterations "times over" w * h "pixels..."]
iterate-time: delta-time [
    repeat i iterations [
        mp/eval/each :iterate pixels
        if zero? i % 50 [prin ["^M " i]]
    ]
    print ""
    mp/eval/each :shade pixels
]

print "Making the image..."
image-time: delta-time [
    rgb: make binary! w * h * 3
    foreach p pixels [
        append rgb as-color p/r p/g p/b
    ]
    img: make image! size
    img/rgb: rgb
    save out-file img
]

print-hline
print ["Pixels:          " w * h]
print ["Preparing:       " prepare-time "(Rebol)"]
print ["Iterating:       " iterate-time "(" iterations "x eval/each + shading)"]
print ["Making the image:" image-time "(Rebol)"]
print ["Saved:" as-yellow mold out-file]
