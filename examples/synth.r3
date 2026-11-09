Rebol [
	title: "Rebol/MathPresso synthesizer with a scope"
	needs: 3.22.14
	purpose: {
		Sound made by MathPresso, heard through Rebol/MiniAudio and seen on
		an oscilloscope in a Pugl window.

		A voice is one formula of `p` (the phase, in cycles) and `time`.
		The same formula is compiled twice:

		* for the sound, `render/with` evaluates it into a float32! vector -
		  through an image one pixel high, whose `x` is the sample's index -
		  and the vector goes straight into a MiniAudio stream;
		* for the scope, `render/with` evaluates it for every pixel of the
		  picture - its column is the phase, its row is lit near the value -
		  and the buffer keeps the glow fading like a phosphor.

		The voice is chosen by radio buttons; the sliders set the pitch, the
		modulation and the volume. The keys A W S E D F T G Y H U J K play
		the notes of an octave from the pitch. Space mutes, Escape closes.

		Per frame there is no loop in Rebol, and nothing is allocated.
	}
]

       import 'pugl
mp:    import 'mathpresso
audio: import 'miniaudio
ui:    do %../../Rebol-Pugl/widgets.reb


;;-- the voices -----------------------------------------------------------------

;; Shared by the sound and the scope. `p0` and `start` are where the current
;; chunk of samples begins: the phase in cycles and the sample's number.
;;
;; The modulation and the volume go from their value at the chunk's start
;; (mod0, vol0) to the one set by the sliders (mod1, vol1) gradually, sample
;; by sample - a jump between two chunks would be heard as a click.
voice!: make struct! [
	p0    [double!]
	start [double!]
	freq  [double!]   ;; Hz
	mod0  [double!]   ;; 0 .. 1, what it does is up to the voice
	mod1  [double!]
	vol0  [double!]
	vol1  [double!]
]
v: make voice! [freq: 220.0 mod0: 0.5 mod1: 0.5 vol0: 0.3 vol1: 0.3]

;; Each voice sets `s`, the sound from -1 to 1, from `p` and `time`. The
;; phase only grows, so a voice using `p * 1.5` stays smooth when the pitch
;; changes - any formula of `p` does.
voices: [
	Organ {
// Drawbars of an organ - `mod` brings in the higher ones.
var s = sin(2 * PI * p)
      + 0.5 * sin(4 * PI * p)
      + mod * (0.5 * sin(6 * PI * p) + 0.35 * sin(8 * PI * p) + 0.25 * sin(12 * PI * p));
s = s * 0.5 * (1 + 0.05 * sin(2 * PI * 6 * time));
}
	Bell {
// FM bell, struck twice a second - `mod` makes it brighter.
var env = exp(-frac(time * 2) * 5);
var s = env * sin(2 * PI * p + (0.5 + 6 * mod) * env * sin(2 * PI * p * 3.5));
}
	Wobble {
// Wobble bass: a sine overdriven by an LFO - `mod` sets how much.
var lfo = 0.5 + 0.5 * sin(2 * PI * 3 * time);
var drive = 1 + mod * 10 * lfo;
var s = tanh(drive * (sin(2 * PI * p) + 0.3 * sin(4 * PI * p))) * 0.8;
}
	Chord {
// A major chord, slowly swelling - `mod` adds the octaves above.
var s = (sin(2 * PI * p) + sin(2 * PI * p * 1.2599) + sin(2 * PI * p * 1.4983)
      + mod * 0.5 * (sin(4 * PI * p) + sin(4 * PI * p * 1.2599) + sin(4 * PI * p * 1.4983)))
      * 0.3 * (0.8 + 0.2 * sin(2 * PI * 0.5 * time));
}
]
voice: 'Organ

;; Sample `x` of the chunk.
sound-head: {
var p = p0 + freq * x / rate;
var time = (start + x) / rate;
var mod = mod0 + (mod1 - mod0) * x / chunk;
}
sound-tail: {
buf = (vol0 + (vol1 - vol0) * x / chunk) * s;
}
;; The scope shows 20 ms, so more cycles of a higher note - starting at a
;; whole cycle, so the picture stands still.
scope-head: {
var p = floor(p0) + x / width * freq * 0.02;
var time = start / rate + x / width * 0.02;
var mod = mod1;
}
scope-tail: {
// Lit near the value; what is not lit again fades like a phosphor.
var yc = height / 2 - s * height * 0.4;
var d = y - yc;
var glow = exp(-d * d * 0.3) + 0.3 * exp(-d * d * 0.01);
buf = max(buf * 0.8, glow);
r = 255 * min(1, buf * 0.35);
g = 255 * min(1, buf);
b = 255 * min(1, buf * 0.55);
}

;;-- the audio ------------------------------------------------------------------

device:  audio/init-playback 1
rate:    device/sample-rate
chunk:   1024                                  ;; samples made at once
samples: make vector! compose [float32! (chunk)]
row:     make image! as-pair chunk 1           ;; only gives `x` to the sound
stream:  audio/make-stream-node/format 0:0:0.2 audio/format_f32

;;-- the scope ------------------------------------------------------------------

scope-size: 480x240
pic:   make image! scope-size
glow:  make vector! compose [float32! (to integer! scope-size/x * scope-size/y)]

sound-fx: scope-fx: none
rebuild: does [
	t: now/precise
	body: voices/:voice
	sound-fx: mp/compile
		mp/context/pixels/with voice! compose [rate (rate) chunk (chunk)]
		ajoin [sound-head body sound-tail]
	scope-fx: mp/compile
		mp/context/pixels/with voice! compose [
			rate   (rate)
			width  (to integer! scope-size/x)
			height (to integer! scope-size/y)
		]
		ajoin [scope-head body scope-tail]
	info2/text: ajoin ["Compiled in " round/to 1000 * to decimal! difference now/precise t 0.01 " ms"]
]

;; The next chunk of samples into the stream.
fill: does [
	mp/render/with :sound-fx v row samples
	audio/write stream samples
	v/p0:    v/p0 + (v/freq * chunk / rate)
	v/start: v/start + chunk
	v/mod0:  v/mod1
	v/vol0:  v/vol1
]

;;-- window ---------------------------------------------------------------------

win: open-window/title 760x400 "MathPresso synthesizer"

ui/init win

bg:     add-image/size win make image! [1x1 30.30.38] 0x0 win/size
canvas: add-image win pic 220x12
canvas/filter: 'linear

;; The scope: as big as fits right of the controls, keeping its aspect.
fit: does [
	bg/size: win/size
	room: as-pair max 64 win/size/x - 232  max 32 win/size/y - 24
	k: min room/x / scope-size/x room/y / scope-size/y
	canvas/size: as-pair to integer! scope-size/x * k  to integer! scope-size/y * k
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

heading "Voice" 12
set-of: copy []
y: 32
foreach [name src] voices [
	c: either name = voice [
		ui/make-choice/radio/checked win form name as-pair 12 y set-of
	][	ui/make-choice/radio         win form name as-pair 12 y set-of ]
	c/action: func [c][voice: to word! c/text  rebuild]
	y: y + 20
]

base: 220.0                                    ;; the pitch slider's note
pitch-label: heading "" 128
pitch-slider: ui/make-slider/value win 12x146 180x18 0.5
pitch-slider/action: func [s][
	base: v/freq: 55.0 * (16 ** s/value)       ;; 55 .. 880 Hz, 220 in the middle
	pitch-label/text: ajoin ["Pitch: " to integer! round base " Hz"]
]

mod-label: heading "" 172
mod-slider: ui/make-slider/value win 12x190 180x18 0.5
mod-slider/action: func [s][
	v/mod1: s/value
	mod-label/text: ajoin ["Modulation: " to integer! round s/value * 100 "%"]
]

volume: 0.3
vol-label: heading "" 216
vol-slider: ui/make-slider/value win 12x234 180x18 0.5
vol-slider/action: func [s][
	volume: s/value * 0.6
	unless mute/on? [v/vol1: volume]
	vol-label/text: ajoin ["Volume: " to integer! round s/value * 100 "%"]
]

mute: ui/make-button/toggle win "Mute" 12x264 70x0
mute/action: func [b][
	v/vol1: either b/on? [0.0][volume]
	ui/set-text b either b/on? ["Unmute"]["Mute"]
]
foreach s reduce [pitch-slider mod-slider vol-slider][s/action s]

info:  heading "" 300
info2: heading "" 318

;; The keys of an octave, as on a piano: white keys on the middle row.
notes: "awsedftgyhujk"

rebuild

;;-- the loop -------------------------------------------------------------------

fill                                           ;; something to start with
hum: audio/play stream

frames: 0
work: 0.0

forever [
	foreach evt poll-events [
		unless ui/handle evt [
			switch evt/type [
				close     [if evt/source == win [close-window win]]
				resize    [fit]
				key       [
					either evt/key = #" " [ui/click mute][
						if n: find notes evt/key [
							v/freq: base * (2 ** ((index? n) - 1 / 12))
						]
					]
				]
				named-key [if evt/key = 'escape [close-window win]]
			]
		]
		unless win/open? [break]
	]
	unless win/open? [break]

	;; Keep the stream topped up - it holds 0.2 s, so this loop may be late.
	while [stream/available >= chunk] [fill]

	t: now/precise
	mp/render/with :scope-fx v pic glow
	redraw canvas
	work: work + to decimal! difference now/precise t
	if 30 = frames: frames + 1 [
		info/text: ajoin ["Scope: " round/to work / frames * 1000 0.1 " ms"]
		frames: 0  work: 0.0
	]
	wait 0.01
]

audio/stop hum
release device
