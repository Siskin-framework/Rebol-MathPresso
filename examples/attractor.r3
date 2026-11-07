Rebol [
    title:   "Strange attractor"
    file:    %attractor.r3
    purpose: {
        Demonstrates `eval/each`, constants and the Rebol/MathPresso
        extension used for generative art.

        Thousands of points jump around the Clifford attractor:
            x' = sin(a * y) + c * cos(a * x)
            y' = sin(b * x) + d * cos(b * y)
        One `eval/each` call moves all points by one step and also computes
        the pixel each point hits, so Rebol only counts the hits. The counts
        are then turned into colours by a second expression.
    }
    needs:   3.22.10
    license: MIT
    url:     https://github.com/Siskin-framework/Rebol-MathPresso
]

mp: import 'mathpresso

size:     800x640
count:    50000      ;; number of points
steps:    60         ;; steps of every point
warm-up:  10         ;; first steps are not drawn (points are not yet on the attractor)
preset:   1          ;; which of the `presets` to draw
out-file: %attractor.png

;; Parameters a b c d of some nice looking attractors.
presets: [
    [-1.4  1.6  1.0   0.7 ]
    [ 1.7  1.7  0.06  1.2 ]
    [-1.7  1.3 -0.1  -1.21]
]
set [a b c d] presets/:preset

w: to integer! size/x
h: to integer! size/y

;; All values of the attractor are within -1-|c| .. 1+|c| (horizontally)
;; and -1-|d| .. 1+|d| (vertically), so fit this area into the image.
scale: 0.95 * min w / (2 * (1 + abs c))  h / (2 * (1 + abs d))

;; State of one point.
point!: make struct! [
    x   [double!]
    y   [double!]
    idx [double!]    ;; index of the pixel hit by the point (0 = outside)
]

space: mp/context/with point! compose [
    a (a)  b (b)  c (c)  d (d)
    width  (w)
    height (h)
    left   (w / -2 / scale)   ;; x at the left edge of the image
    top    (h /  2 / scale)   ;; y at the top edge of the image
    scale  (scale)            ;; pixels per unit
]

move: mp/compile :space {
// One step of the Clifford attractor.
var nx = sin(a * y) + c * cos(a * x);
var ny = sin(b * x) + d * cos(b * y);
x = nx;
y = ny;
// Pixel hit by the point (1-based index into the image), or 0 when outside.
var sx = (x - left) * scale;
var sy = (top - y) * scale;
var inside = (sx >= 0) * (sx < width) * (sy >= 0) * (sy < height);
idx = inside * (1 + floor(sx) + floor(sy) * width);
}

;; State of one pixel.
pixel!: make struct! [
    n [double!]                            ;; number of hits
    r [double!]  g [double!]  b [double!]  ;; its colour
]

points: make vector! reduce [:point! count]
counts: make vector! compose [integer! 32 (w * h)]

print ["Moving" count "points" steps "times..."]
move-time: delta-time [
    random/seed 1
    foreach p points [
        p/x: (random 4.0) - 2.0
        p/y: (random 4.0) - 2.0
    ]
    repeat s steps [
        mp/eval/each :move points
        if s > warm-up [
            foreach p points [
                if 0 < i: to integer! p/idx [counts/:i: counts/:i + 1]
            ]
        ]
        prin ["^M " s]
    ]
    print ""
]

print "Shading..."
shade-time: delta-time [
    pixels: make vector! reduce [:pixel! w * h]
    most: 1
    i: 1
    foreach p pixels [
        p/n: to decimal! n: counts/(++ i)
        if n > most [most: n]
    ]
    ;; `most` is known only now, so the shading is compiled only now.
    shade: mp/compile (mp/context/with pixel! compose [most (most)]) {
// Logarithmic density, so rarely visited pixels are still visible.
var v = pow(log(1 + n) / log(1 + most), 0.75);
r = 255 * min(1, v * 1.6);
g = 255 * min(1, pow(v, 1.6) * 1.2);
b = 255 * min(1, 0.25 * sqrt(v) + v * v * v);
}
    mp/eval/each :shade pixels
]

print "Making the image..."
image-time: delta-time [
    rgb: make binary! w * h * 3
    foreach p pixels [
        append rgb to integer! p/r
        append rgb to integer! p/g
        append rgb to integer! p/b
    ]
    img: make image! size
    img/rgb: rgb
    save out-file img
]

print-hline
print ["Attractor:       " mold presets/:preset]
print ["Hits:            " count * (steps - warm-up)]
print ["Moving:          " move-time "(" steps "x eval/each + counting in Rebol)"]
print ["Shading:         " shade-time]
print ["Making the image:" image-time "(Rebol)"]
print ["Saved:" as-yellow mold out-file]
