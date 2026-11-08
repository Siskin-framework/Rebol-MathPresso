Rebol [
	title: "Rebol/MathPresso animated shader demo"
	needs: 3.22.14
	purpose: {
		Pixel effects in a Pugl window: every frame, `render` evaluates one
		compiled expression for each pixel of an image - like a pixel
		shader, but on the CPU, in code MathPresso generated.

		The effect is chosen by radio buttons; the sliders set its speed,
		its zoom and the resolution it is rendered at. Most effects follow
		the pointer. Space pauses, Escape closes.

		What changes every frame - the time, the zoom and the pointer - is
		in a struct, so it needs no new compilation. The image's size is
		passed as constants, so a new resolution compiles the effect again
		(see how long that takes, below the controls).

		Per frame there is no loop in Rebol, and nothing is allocated.
	}
]

mp: import 'mathpresso
ui: do %../../Rebol-Pugl/widgets.reb


;;-- the effects ----------------------------------------------------------------

;; What changes from frame to frame - read by the expressions, never written.
frame!: make struct! [
	t    [double!]   ;; time, in seconds (times the speed)
	zoom [double!]   ;; 1.0 by default
	mx   [double!]   ;; the pointer, in the image's pixels
	my   [double!]
]

;; MathPresso has no loops, so the Julia set's step is simply repeated -
;; written out `steps` times into one long expression.
julia: function [steps [integer!]][
	src: copy {
// The Julia set of a point c going round: z = z * z + c, done many times.
var cr = 0.7885 * cos(t * 0.25);
var ci = 0.7885 * sin(t * 0.25);
var zr = (x - width / 2) / height * 3 / zoom;
var zi = (y - height / 2) / height * 3 / zoom;
var n = 0;
var zr2; var zi2; var in;
}
	loop steps [append src {zr2 = zr * zr; zi2 = zi * zi; in = zr2 + zi2 < 256;
zi = zi + in * (2 * zr * zi + ci - zi); zr = zr + in * (zr2 - zi2 + cr - zr); n = n + in;
}]
	append src ajoin [{// Smooth colouring of the steps it took to escape.
var m = max(zr * zr + zi * zi, 1.0001);
var mu = n + 1 - log2(0.5 * log(m));
var e = n < } steps {;
var c = sqrt(max(mu, 0)) * 0.2;
r = e * 255 * (0.5 + 0.5 * cos(2 * PI * (c + 0.00)));
g = e * 255 * (0.5 + 0.5 * cos(2 * PI * (c + 0.15)));
b = e * 255 * (0.5 + 0.5 * cos(2 * PI * (c + 0.30)));
}]
]

;; Besides x y r g b a (from /pixels) and the fields of `frame!`, every
;; effect knows the constants `width` and `height` - the image's size.
effects: reduce [
	'Plasma {
// Four sine waves - the last one circles around the pointer.
var u = (x - width / 2) / zoom;
var v = (y - height / 2) / zoom;
var p = sin(u * 0.05 + t)
      + sin(v * 0.04 - t * 1.3)
      + sin((u + v) * 0.03 + t * 0.7)
      + sin(hypot(x - mx, y - my) / zoom * 0.06 - t * 2);
var c = p * 0.125 + 0.5;
r = 255 * (0.5 + 0.5 * cos(2 * PI * (c + 0.00)));
g = 255 * (0.5 + 0.5 * cos(2 * PI * (c + 0.33)));
b = 255 * (0.5 + 0.5 * cos(2 * PI * (c + 0.67)));
}
	'Tunnel {
// A checkered tunnel: the closer to its centre, the deeper.
var dx = x - width / 2 - (mx - width / 2) * 0.3;
var dy = y - height / 2 - (my - height / 2) * 0.3;
var d = max(hypot(dx, dy), 1);
var depth = height * 0.3 * zoom / d + t * 0.6;
var turn  = atan2(dy, dx) / PI + t * 0.05;
var c = smoothstep(-0.15, 0.15, sin(depth * PI * 2) * sin(turn * PI * 6));
var fog = min(1, d / height * 3);
r = 255 * fog * (0.20 + 0.70 * c);
g = 255 * fog * (0.10 + 0.45 * c);
b = 255 * fog * (0.40 + 0.30 * c);
}
	'Metaballs {
// Three blobs flying around and one at the pointer, melting together.
var s = height * 0.07 * zoom;
var f = s / hypot(x - width * (0.5 + 0.30 * sin(t * 0.8)), y - height * (0.5 + 0.30 * cos(t * 1.1)))
      + s / hypot(x - width * (0.5 + 0.25 * cos(t * 0.6)), y - height * (0.5 + 0.35 * sin(t * 0.9)))
      + s / hypot(x - width * (0.5 + 0.35 * sin(t * 1.3)), y - height * (0.5 + 0.20 * sin(t * 0.7)))
      + s / hypot(x - mx, y - my);
var inside = smoothstep(0.95, 1.05, f);
var core = min(1, (f - 1) * 0.5);
var glow = min(1, f * 0.8);
r = 255 * mix(glow * glow * 0.35, 1.0, inside);
g = 255 * mix(glow * 0.20, 0.50 + 0.45 * core, inside);
b = 255 * mix(glow * 0.55, 0.15 + 0.60 * core, inside);
}
	'Rings {
// Waves from two sources - one follows the pointer - and their interference.
var d1 = hypot(x - mx, y - my);
var d2 = hypot(x - width * (0.5 + 0.3 * cos(t * 0.5)), y - height * (0.5 + 0.3 * sin(t * 0.7)));
var v = (sin(d1 * 0.3 / zoom - t * 4) + sin(d2 * 0.3 / zoom - t * 4)) * 0.5;
r = 90 + 90 * v;
g = 150 + 70 * v;
b = 200 + 55 * v;
}
	'Warp {
// Domain warping: the point is moved by waves before it is coloured.
var u = (x - width / 2) / height * 3 / zoom;
var v = (y - height / 2) / height * 3 / zoom;
var q1 = sin(u * 1.7 + t * 0.4) + cos(v * 1.3 - t * 0.3);
var q2 = cos(u * 1.1 - t * 0.2) + sin(v * 1.9 + t * 0.5);
var u2 = u + q1 + (mx / width - 0.5);
var v2 = v + q2 + (my / height - 0.5);
var p = 0.5 + 0.5 * sin(u2 * 2 + sin(v2 * 3 + t));
var k = 0.5 + 0.5 * sin(q1 * q2 * 2 + t * 0.3);
r = 255 * mix(0.05, 0.95, p * p);
g = 255 * mix(0.10, 0.75, p) * mix(0.6, 1.0, k);
b = 255 * mix(0.30, 0.40, p * k);
}
	'Julia julia 48
]

sizes:  [160x120 240x180 320x240 480x360 640x480]   ;; chosen by a slider
res:    320x240
effect: 'Plasma
speed:  1.0
f:      make frame! [zoom: 1.0]
f/mx:   res/x / 2
f/my:   res/y / 2
pic:    make image! res
fx:     none
dirty?: true

;; Compiles the effect for the current resolution.
rebuild: does [
	t: now/precise
	fx: mp/compile
		mp/context/pixels/with frame! compose [
			width  (to integer! res/x)
			height (to integer! res/y)
		]
		select effects effect
	info2/text: ajoin ["Compiled in " round/to 1000 * to decimal! difference now/precise t 0.01 " ms"]
	dirty?: true
]

;; A new resolution: a new image, the pointer kept where it was.
set-resolution: func [new [pair!]][
	f/mx: f/mx * new/x / res/x
	f/my: f/my * new/y / res/y
	res: new
	pic: make image! res
	canvas/image: pic
	fit
	rebuild
]

;;-- window ---------------------------------------------------------------------

win: open-window/title 760x540 "MathPresso shaders"

ui/init win

bg:     add-image/size win make image! [1x1 30.30.38] 0x0 win/size
canvas: add-image win pic 220x12
canvas/filter: 'linear

;; The picture: as big as fits right of the controls, keeping its aspect.
fit: does [
	bg/size: win/size
	room: as-pair max 64 win/size/x - 232  max 48 win/size/y - 24
	k: min room/x / res/x room/y / res/y
	canvas/size: as-pair to integer! res/x * k  to integer! res/y * k
	canvas/offset: as-pair
		220 + to integer! (room/x - canvas/size/x) / 2
		12  + to integer! (room/y - canvas/size/y) / 2
]
fit

heading: function [text y][
	h: ui/add-label win text as-pair 12 y
	h/tint: 170.170.185
	h
]

heading "Effect" 12
set-of: copy []
y: 32
foreach [name src] effects [
	c: either name = effect [
		ui/make-choice/radio/checked win form name as-pair 12 y set-of
	][	ui/make-choice/radio         win form name as-pair 12 y set-of ]
	c/action: func [c][effect: to word! c/text  rebuild]
	y: y + 20
]

speed-label: heading "" 168
speed-slider: ui/make-slider/value win 12x186 180x18 0.5
speed-slider/action: func [s][
	speed: s/value * 2                       ;; 0 .. 2, 1.0 in the middle
	speed-label/text: ajoin ["Speed: " round/to speed 0.01]
]

zoom-label: heading "" 212
zoom-slider: ui/make-slider/value win 12x230 180x18 0.5
zoom-slider/action: func [s][
	f/zoom: 0.25 * (16 ** s/value)           ;; 0.25 .. 4, 1.0 in the middle
	zoom-label/text: ajoin ["Zoom: " round/to f/zoom 0.01]
	dirty?: true
]

res-label: heading "" 256
res-slider: ui/make-slider/value/steps win 12x274 180x18 0.5 4
res-slider/action: func [s /local new][
	new: pick sizes 1 + to integer! round s/value * 4
	res-label/text: ajoin ["Resolution: " to integer! new/x "x" to integer! new/y]
	if new <> res [set-resolution new]
]
;; the labels show the values from the start
foreach s reduce [speed-slider zoom-slider res-slider][s/action s]

pause: ui/make-button/toggle win "Pause" 12x304 70x0
pause/action: func [b][ui/set-text b either b/on? ["Play"]["Pause"]]
restart: ui/make-button win "Restart" 90x304 0x0
restart/action: func [b][f/t: 0.0  dirty?: true]

info:  heading "" 340
info2: heading "" 358

rebuild

;;-- the loop -------------------------------------------------------------------

t0: now/precise
frames: 0
work: 0.0

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
		;; The pointer, in the image's pixels - also outside of it.
		if evt/type = 'move [
			p: evt/offset - canvas/offset
			f/mx: p/x * res/x / canvas/size/x
			f/my: p/y * res/y / canvas/size/y
			dirty?: true
		]
		unless win/open? [break]
	]
	unless win/open? [break]

	t: now/precise
	dt: min 0.1 to decimal! difference t t0
	t0: t
	unless pause/on? [
		f/t: f/t + (speed * dt)
		dirty?: true
	]
	if dirty? [
		mp/render :fx f pic
		redraw canvas
		dirty?: false
		work: work + to decimal! difference now/precise t
		if 30 = frames: frames + 1 [
			info/text: ajoin ["Frame: " round/to work / frames * 1000 0.1 " ms"]
			frames: 0  work: 0.0
		]
	]
	wait 0.01
]
