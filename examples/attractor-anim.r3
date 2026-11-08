Rebol [
	title: "Rebol/MathPresso animated strange attractor"
	needs: 3.22.14
	purpose: {
		A Clifford attractor whose parameters slowly drift, in a Pugl
		window: thousands of points jump around it, and what they hit
		glows and fades.

		Every frame:
		* the step expression is compiled again - the parameters a b c d
		  are constants, so it is as fast as it gets (compiling takes
		  a fraction of a millisecond);
		* `eval/each` moves all the points and gives each the pixel it hits;
		* Rebol counts the hits into a vector of densities - the only loop
		  in Rebol, as one expression cannot write into another pixel;
		* `render/with` fades the densities and colours the image.

		The palette is chosen by radio buttons; the sliders set the speed of
		the drift, the length of the trails and the brightness. Space pauses,
		Escape closes.
	}
]

import pugl
mp: import 'mathpresso
ui: do %../../Rebol-Pugl/widgets.reb


;;-- the points -----------------------------------------------------------------

res:   400x400
w:     to integer! res/x
h:     to integer! res/y
count: 20000      ;; points
life:  60         ;; steps a point lives before it starts again elsewhere

point!: make struct! [
	x    [double!]
	y    [double!]
	idx  [double!]   ;; the pixel it hits, 1-based - or 0 when outside
	age  [double!]
	seed [double!]
]

points: make vector! reduce [:point! count]
random/seed 1
foreach p points [
	p/x:    (random 4.0) - 2.0
	p/y:    (random 4.0) - 2.0
	p/age:  to decimal! random life     ;; so they do not all start again at once
	p/seed: to decimal! random 1000000
]

step-src: {
// When the attractor changes, its points could all fall into one cycle and
// stay there - so a point lives only `life` steps, then starts elsewhere.
var dead = age >= life;
seed = seed + dead;
x = x + dead * (hash(seed) * 4 - 2 - x);
y = y + dead * (hash(seed + 0.5) * 4 - 2 - y);
age = age * (1 - dead) + 1;

// One step of the Clifford attractor.
var nx = sin(a * y) + c * cos(a * x);
var ny = sin(b * x) + d * cos(b * y);
x = nx;
y = ny;

// The pixel it hits - its first steps are not drawn, it is not there yet.
var sx = x * scale + width / 2;
var sy = height / 2 - y * scale;
var inside = (age > 3) * (sx >= 0) * (sx < width) * (sy >= 0) * (sy < height);
idx = inside * (1 + floor(sx) + floor(sy) * width);
}

;; The constants of the step expression - a b c d are set every frame.
consts: compose [
	a 0.0  b 0.0  c 0.0  d 0.0
	life   (life)
	width  (w)
	height (h)
	scale  (w / 2 / 2.4)   ;; all of it fits: |x| <= 1 + |c|, |y| <= 1 + |d|
]

;;-- the picture ----------------------------------------------------------------

shade!: make struct! [
	fade [double!]   ;; how much of the density is left after a frame
	gain [double!]   ;; brightness
]
sh: make shade! [fade: 0.92 gain: 0.5]

shade-head: {
// The density fades a little every frame: what is not hit again goes dark.
buf = buf * fade;
// Logarithmic, so rarely visited pixels are still visible.
var v = min(1, log(1 + buf * gain) / log(1 + 40 * gain));
}
palettes: [
	Fire {
r = 255 * min(1, v * 1.5);
g = 255 * min(1, pow(v, 1.7) * 1.3);
b = 255 * min(1, 0.3 * sqrt(v) + pow(v, 3));
}
	Ice {
r = 255 * min(1, 0.3 * sqrt(v) + pow(v, 3));
g = 255 * min(1, pow(v, 1.7) * 1.3);
b = 255 * min(1, v * 1.5);
}
	Mono {
r = 255 * sqrt(v);
g = 255 * sqrt(v);
b = 255 * sqrt(v);
}
]
palette: 'Fire

dens:   make vector! compose [float64! (w * h)]   ;; hits, fading
pic:    make image! res
shader: none
rebuild-shade: does [
	shader: mp/compile mp/context/pixels shade! join shade-head select palettes palette
]
rebuild-shade

t:     0.0        ;; the drift's own time
speed: 1.0

;;-- window ---------------------------------------------------------------------

win: open-window/title 760x540 "MathPresso strange attractor"

ui/init win

bg:     add-image/size win make image! [1x1 0.0.0] 0x0 win/size
canvas: add-image win pic 220x12
canvas/filter: 'linear

;; The picture: square, as big as fits right of the controls.
fit: does [
	bg/size: win/size
	side: to integer! max 64 min win/size/x - 232 win/size/y - 24
	canvas/size: as-pair side side
	canvas/offset: as-pair 220 + to integer! (win/size/x - 232 - side) / 2  12
]
fit

heading: function [text y][
	h: ui/add-label win text as-pair 12 y
	h/tint: 170.170.185
	h
]

heading "Palette" 12
set-of: copy []
y: 32
foreach [name src] palettes [
	c: either name = palette [
		ui/make-choice/radio/checked win form name as-pair 12 y set-of
	][	ui/make-choice/radio         win form name as-pair 12 y set-of ]
	c/action: func [c][palette: to word! c/text  rebuild-shade]
	y: y + 20
]

speed-label: heading "" 108
speed-slider: ui/make-slider/value win 12x126 180x18 0.5
speed-slider/action: func [s][
	speed: s/value * 2                         ;; 0 .. 2, 1.0 in the middle
	speed-label/text: ajoin ["Drift: " round/to speed 0.01]
]

trail-label: heading "" 152
trail-slider: ui/make-slider/value win 12x170 180x18 0.5
trail-slider/action: func [s][
	sh/fade: 1.0 - (0.32 * (0.0625 ** s/value)) ;; 0.68 .. 0.98, 0.92 in the middle
	trail-label/text: ajoin ["Trails: " round/to sh/fade 0.001]
]

gain-label: heading "" 196
gain-slider: ui/make-slider/value win 12x214 180x18 0.5
gain-slider/action: func [s][
	sh/gain: 0.05 * (100 ** s/value)          ;; 0.05 .. 5, 0.5 in the middle
	gain-label/text: ajoin ["Brightness: " round/to sh/gain 0.01]
]
foreach s reduce [speed-slider trail-slider gain-slider][s/action s]

pause: ui/make-button/toggle win "Pause" 12x244 70x0
pause/action: func [b][ui/set-text b either b/on? ["Play"]["Pause"]]

info:   heading "" 280
params: heading "" 298

;;-- the loop -------------------------------------------------------------------

t0: now/precise
frames: 0
work: 0.0
compiling: 0.0

forever [
	foreach evt poll-events [
		unless ui/handle evt [
			switch evt/type [
				close     [if evt/source == win [close-window win]]
				resize    [fit]
				key       [if evt/key = #" " [ui/click pause]]
				named-key [if evt/key = 'escape [close-window win]]
			]
		]
		unless win/open? [break]
	]
	unless win/open? [break]

	now-t: now/precise
	dt: min 0.1 to decimal! difference now-t t0
	t0: now-t
	unless pause/on? [
		t: t + (speed * dt)
		;; The parameters drift around a known good attractor.
		consts/2: -1.4 + (0.25 * sine/radians t * 0.31)
		consts/4:  1.6 + (0.20 * sine/radians t * 0.37 + 1)
		consts/6:  1.0 + (0.20 * sine/radians t * 0.23 + 2)
		consts/8:  0.7 + (0.25 * sine/radians t * 0.29 + 3)

		c0: now/precise
		stepper: mp/compile mp/context/with point! consts step-src
		compiling: compiling + to decimal! difference now/precise c0

		mp/eval/each :stepper points
		foreach p points [
			if 0 < i: to integer! p/idx [dens/:i: dens/:i + 1.0]
		]
		mp/render/with :shader sh pic dens
		redraw canvas

		work: work + to decimal! difference now/precise now-t
		if 30 = frames: frames + 1 [
			info/text: ajoin [
				"Frame: " round/to work / frames * 1000 0.1 " ms"
				" (compile " round/to compiling / frames * 1000 0.01 " ms)"
			]
			params/text: ajoin [
				"a " round/to consts/2 0.01 "  b " round/to consts/4 0.01
				"  c " round/to consts/6 0.01 "  d " round/to consts/8 0.01
			]
			frames: 0  work: compiling: 0.0
		]
	]
	wait 0.01
]
