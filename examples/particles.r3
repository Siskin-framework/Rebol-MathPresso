Rebol [
    title:   "Particle fountains"
    file:    %particles.r3
    purpose: {
        Demonstrates `eval/each` of the Rebol/MathPresso extension.

        The whole simulation - respawning, gravity, air drag, bouncing on
        the floor and colouring - is one compiled expression, evaluated
        for every particle of a vector of structs by a single command call
        per frame. Rebol only draws the result and saves it as PNG frames.

        Make a video from the frames with e.g.:
            ffmpeg -framerate 60 -i particles/frame-%04d.png -pix_fmt yuv420p particles.mp4
    }
    needs:   3.22.10
    license: MIT
    url:     https://github.com/Siskin-framework/Rebol-MathPresso
]

mp: import 'mathpresso

size:       640x400
count:      5000       ;; number of particles
warm-up:    180        ;; steps simulated before the first saved frame
frames:     240        ;; frames to save (4 seconds at 60 fps)
out-dir:    %particles/
background: 6.6.14

;; State of one particle. The order of the fields is also the order of the
;; values used to initialize the vector below.
particle!: make struct! [
    x    [double!]  y    [double!]   ;; position
    vx   [double!]  vy   [double!]   ;; velocity
    age  [double!]  life [double!]   ;; seconds lived / seconds to live
    seed [double!]                   ;; drives the pseudo random respawns
    hue  [double!]
    t    [double!]                   ;; clock - drives the moving fountains
    r    [double!]  g    [double!]  b [double!]   ;; colour computed for drawing
]

;; Constants of the simulation. MathPresso folds them into the compiled code,
;; and they need no fields in the struct.
world: mp/context/with particle! compose [
    width   (size/x)
    height  (size/y)
    gravity 420.0       ;; pixels per second squared
    dt      (1.0 / 60)  ;; one step per frame at 60 fps
    drag    0.995
]

;; The simulation step. MathPresso has no `if`, so the comparisons (which give
;; 1.0 or 0.0) are used as masks.
physics: {
// Respawn the particle once its life is over (`dead` is 1.0 or 0.0, so
// every `+ dead * (new - old)` below is a branch-free conditional set).
var dead = age >= life;
seed = seed + dead;
var r1  = frac(sin(seed * 12.9898) * 43758.5453);
var r2  = frac(sin(seed * 78.233)  * 43758.5453);
var r3  = frac(sin(seed * 39.3468) * 24634.6345);
var r4  = frac(sin(seed * 93.9898) * 15731.743);
var src = floor(r4 * 3);                       // which of the three fountains
var ex  = width * (0.2 + 0.3 * src) + 40 * sin(t * 0.7 + src * 2);
var ang = -PI / 2 + (r1 - 0.5) * 0.5 + 0.15 * sin(t * 0.9 + src);
var spd = 380 + r2 * 160;
x    = x    + dead * (ex - x);
y    = y    + dead * (height - 6 - y);
vx   = vx   + dead * (cos(ang) * spd - vx);
vy   = vy   + dead * (sin(ang) * spd - vy);
life = life + dead * (1.8 + r3 * 1.6 - life);
hue  = hue  + dead * (frac(src / 3 + t * 0.03 + r3 * 0.08) - hue);
age  = age  * (1 - dead);

// Integrate: gravity, air drag, and a lossy bounce on the floor.
vy  = (vy + gravity * dt) * drag;
vx  = vx * drag;
x   = x + vx * dt;
y   = y + vy * dt;
var hit = (y > height - 4) * (vy > 0);
vy  = vy - hit * 1.55 * vy;
y   = min(y, height - 4);
age = age + dt;
t   = t + dt;

// Colour: a cosine palette on `hue`, white-hot at birth, fading out.
var k   = max(0, 1 - age / life);
var hot = max(0, 1 - age * 5) * 0.8;
r = min(255, 255 * (k * (0.5 + 0.5 * cos(2 * PI * hue)) + hot));
g = min(255, 255 * (k * (0.5 + 0.5 * cos(2 * PI * (hue - 0.333))) + hot));
b = min(255, 255 * (k * (0.5 + 0.5 * cos(2 * PI * (hue - 0.667))) + hot));
}

step: mp/compile :world physics

;; All particles start below the screen with staggered lives, so they are
;; born gradually instead of all in the very first step.
data: make block! count * 12
repeat i count [
    repend data [
        0.0  size/y + 50.0  0.0  0.0   ;; x y vx vy
        0.0  random 2.5                ;; age life
        i * 7.13  0.0  0.0             ;; seed hue t
        0.0  0.0  0.0                  ;; r g b
    ]
]
particles: make vector! reduce [particle! data]

;; Each particle is drawn as a short streak behind it, fading along its
;; length. Colours are added to what is already there (tuples saturate at
;; 255), so dense areas glow.
render: function [
    "Draws the particles into an image"
    img [image!]
    ps  [vector!]
][
    w: img/size/x
    h: img/size/y
    repeat i length? ps [
         p: ps/:i
         x: p/x
         y: p/y
        dx: p/vx * 0.004
        dy: p/vy * 0.004
        clr: as-color p/r p/g p/b
        loop 6 [
            if all [x >= 0  y >= 0  x < w  y < h][
                pos: as-pair 1 + to integer! x 1 + to integer! y
                poke img pos clr + pick img pos
            ]
            x: x - dx
            y: y - dy
            clr: clr * 0.75
        ]
    ]
    img
]

make-dir out-dir
sim-time:  0:0:0
draw-time: 0:0:0

print ["Warming up" warm-up "steps..."]
loop warm-up [mp/eval/each :step particles]

print ["Saving" frames "frames into" mold out-dir]
img: make image! reduce [size background]
repeat frame frames [
    ;; One command call moves every particle.
    sim-time:   sim-time + delta-time [mp/eval/each :step particles]
    draw-time: draw-time + delta-time [
        img/rgb: background 
        render :img particles
    ]
    save rejoin [out-dir %frame- next form 10000 + frame %.png] img
    prin ["^M frame" frame]
]
print ""

print-hline
print ["Particles:           " count]
print ["Simulation per frame:" sim-time / frames  "(one eval/each)"]
print ["Drawing per frame:   " draw-time / frames "(Rebol)"]
print ["Video:" as-yellow "ffmpeg -framerate 60 -i particles/frame-%04d.png -pix_fmt yuv420p particles.mp4"]
